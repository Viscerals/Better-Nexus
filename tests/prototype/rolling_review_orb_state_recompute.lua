-- Review finding F1 on range eadff8a..578c77e: automatic rolling did not evaluate
-- again when the Orb state changed from unknown to known on an unchanged board,
-- and the status text stayed stale. NEW test written from the independent
-- review's reproduction. Real runtime, real gate, real mutators; mocked game
-- services; no native evidence.
local H=dofile('tests/prototype/harness.lua');H.pendingRolls=6;H.Boot()
local A=Nexus.GameAdapter
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
check(A.SetFirstLoadoutWishlistIdentity('F1 plan',{ {spellId=200001,quality=1,stacks=2} }),'plan set')
local known,pending=false,false
ProjectEbonhold.OrbService={IsStateKnown=function()return known end,IsOfferPending=function()return pending end}
H.Board({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}});H.Notify();H.Advance(.5)
local n=#H.actions
SlashCmdList.NEXUS('auto');H.Advance(3,.1)
check(#H.actions==n,'unknown Orb state: automatic rolling sends nothing')
-- Unknown -> known. No game event follows. The board is unchanged.
known=true;H.Advance(3,.1)
check(#H.actions==n+1,'known Orb state on an unchanged board: automatic rolling evaluates again and acts once (actions='..(#H.actions-n)..')')
check(H.actions[#H.actions][1]=='freeze','the action is the planner decision for this board')
-- Bounded: the state change costs a small number of extra steps, not one per poll.
H.perks.pendingFreezeIndex=nil;H.Advance(1,.1)
local steady=Nexus.RecomputeStats()
H.Advance(20,.1)
local after=Nexus.RecomputeStats()
check((after.polls or 0)-(steady.polls or 0)>=90,'the poll loop ran')
check((after.skipped or 0)-(steady.skipped or 0)>=((after.polls or 0)-(steady.polls or 0))-12,'with no state change the polls are skipped, not recomputed')
-- Known -> unknown -> known again, now in manual mode: the recommendation text follows.
SlashCmdList.NEXUS('auto');H.Advance(.5,.1)
H.Board({{spellId=200001,quality=1},{spellId=200022,quality=0},{spellId=200023,quality=1}});H.Notify();H.Advance(1,.1)
local function shown()
 local m=Nexus.Panel._lastModel or {}
 return tostring(m.status)..' | '..tostring(m.recommendation)
end
local PAUSED='Ordinary rolling paused'
known=false;H.Advance(1,.1)
check(shown():find(PAUSED,1,true)~=nil,'unknown Orb state is shown in the panel status: '..shown())
known=true;H.Advance(1,.1)
check(not shown():find(PAUSED,1,true),'the panel status and recommendation follow the change to known: '..shown())
check((Nexus.Panel._lastModel.recommendation or '')~='','a real recommendation is shown again')
-- Pending -> not pending without a board change also evaluates again.
SlashCmdList.NEXUS('auto');H.Advance(.5,.1)
pending=true;H.Advance(1,.1);local m=#H.actions
H.Advance(2,.1);check(#H.actions==m,'open Orb offer: nothing sent')
pending=false;H.Advance(3,.1)
check(#H.actions==m+1,'offer closed, same board: automatic rolling evaluates again')
print('PASS F1 Orb gate changes trigger one bounded re-evaluation; status text follows checks='..checks)
