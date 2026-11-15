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
-- LEVELING_RARITY: the pure optional rarity-first selector (Policy.lua). It
-- reads only the adapter's observed card rarity (observedQuality); a missing,
-- non-integer, non-finite or out-of-range rarity refuses the whole board and
-- never becomes Common. Ties go to the first card in current offer order.
dofile('logic/Policy.lua')
local P=Nexus.Policy
local function LB(q1,q2,q3,extra)
 local b={cards={{spellId=301,observedQuality=q1},{spellId=302,observedQuality=q2},{spellId=303,observedQuality=q3}}}
 if extra then b.cards[4]={spellId=304,observedQuality=1} end
 return {board=b,level=2,horizon=40,ordinaryBoardAllowed=true}
end
local d=P.DecideLevelingRarity(LB(1,4,2))
check(d.type=='take' and d.index==2 and d.spellId==302 and d.quality==4,'rarities 1/4/2: the quality 4 offer is taken')
d=P.DecideLevelingRarity(LB(4,4,2))
check(d.type=='take' and d.index==1 and d.spellId==301,'4/4/2: the first quality 4 offer wins the tie')
d=P.DecideLevelingRarity(LB(2,4,4))
check(d.type=='take' and d.index==2 and d.spellId==302,'reordered 2/4/4: the first current quality 4 offer wins')
check(P.DecideLevelingRarity(LB(2,4,4)).index==d.index,'the selector is reproducible')
for _,bad in ipairs({{nil,'nil'},{0/0,'NaN'},{1/0,'inf'},{2.5,'fraction'},{5,'above 4'},{-1,'negative'},{'4','string'}}) do
 local r=P.DecideLevelingRarity(LB(bad[1],1,1))
 check(r.type=='wait','an unknown rarity ('..bad[2]..') refuses the whole board, never Common')
end
check(P.DecideLevelingRarity(LB(0,1,2)).index==3,'a valid Common (0) offer is an ordinary rarity')
check(P.DecideLevelingRarity(LB(1,1,1,true)).type=='wait','an oversized board is refused')
local sparse=LB(1,4,2);sparse.board.cards[2]=nil
check(P.DecideLevelingRarity(sparse).type=='wait','a sparse board is refused')
local dup=LB(1,4,2);dup.board.cards[3].spellId=302
check(P.DecideLevelingRarity(dup).type=='wait','one Echo at two rarities is refused')
local badId=LB(1,4,2);badId.board.cards[1].spellId=1.5
check(P.DecideLevelingRarity(badId).type=='wait','an invalid Echo id is refused')
for _,lv in ipairs({1,0,80,81,-3,2.5,'5',0/0}) do
 local s=LB(1,4,2);s.level=lv
 check(P.DecideLevelingRarity(s).type=='wait' and not P.LevelingLevel(lv),'level '..tostring(lv)..' refuses')
end
check(P.LevelingLevel(2) and P.LevelingLevel(79),'levels 2 and 79 are eligible')
local s79=LB(1,4,2);s79.level=79
check(P.DecideLevelingRarity(s79).type=='take','level 79 may take')
local orb=LB(1,4,2);orb.ordinaryBoardAllowed=false
check(P.DecideLevelingRarity(orb).type=='wait','a board the ordinary gate does not allow waits')
local noH=LB(1,4,2);noH.horizon=nil
check(P.DecideLevelingRarity(noH).type=='wait','an unknown pending-pick count waits')
local g=LB(1,4,2);g.board.cards[2].isGuaranteed=true;g.board.cards[1].isFrozen=true
check(P.DecideLevelingRarity(g).index==2,'guaranteed/frozen flags restrict only Banish/Freeze, not Take')
print('PASS echoweaver_planner: exact-copy and safety bridge controls, Orb boards never search checks='..checks)
