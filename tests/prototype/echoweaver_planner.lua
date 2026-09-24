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
print('PASS echoweaver_planner: exact-copy and safety bridge controls checks='..checks)
