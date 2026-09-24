-- Issue #62: a submitted Echo selection is intent, not ownership.
--
-- The adapter submits a Select and holds the client's pending latch. When the
-- latch clears and the board has changed or gone, it used to add that spell to
-- recordedPicks, and Owned() takes the larger of that count and the granted
-- mirror for every spell. So a Select the server never granted could become
-- represented ownership -- progress, targets, the planner and save
-- eligibility all read Owned() -- on nothing but a board transition.
--
-- recordedPicks exists for a real reason: boards auto-chain, and the granted
-- mirror can lag the next board by one pick, so without it the planner could
-- pick the same Echo again. That is duplicate-action suppression, and it must
-- stay. What must not stay is its being counted as owned.
--
-- The invariant these checks enforce:
--   pending Select intent may suppress duplicate submission and block
--   dependent actions, but never counts as owned. Only the granted mirror --
--   the established evidence -- is ownership. Board transitions, latch
--   clearance, elapsed time and a new table reference are not confirmation.
--
-- Everything goes through the real adapter in the real host. Grants are made
-- the way the harness always models them: by changing the granted mirror.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,A

local X,Y,Z=200010,200011,200012
local BOARD={{spellId=X,quality=2},{spellId=Y,quality=1},{spellId=Z,quality=0}}
local NEXT={{spellId=200020,quality=1},{spellId=200021,quality=1},{spellId=200022,quality=1}}

local function Boot(level,granted,mutate)
 H=F.Boot(F.Database({mutate=mutate}),function(h)
  h.playerLevel=level or 30
  if granted then h.granted=granted end
 end)
 A=Nexus.GameAdapter
 check(Nexus.StartupStatus().coreReady==true,'fixture: start-up completed')
 H.Advance(.5)
 return H
end
local function Owned(id) return (A.Owned().bySpell or {})[id] or 0 end
local function ShowBoard(cards) H.Board(cards);H.Notify();A.Poll();H.Advance(.2) end
local function Grant(id,quality)
 local out=H.Clone(H.granted or {})
 local name='Echo '..(id-200000)
 out[name]=out[name] or {}
 table.insert(out[name],{spellId=id,quality=quality or 0})
 H.granted=out;H.Notify();A.Poll();H.Advance(.2)
end
-- The server resolves the Select: the latch clears, and the board is replaced
-- (auto-chain), removed, or left exactly as it was (refusal).
local function Resolve(board)
 H.perks.pendingSelectSpellId=nil
 if board=='same' then
  -- unchanged: the refused offer stays on screen
 elseif board==nil then
  H.perks.currentChoice=nil
 else
  H.Board(board)
 end
 H.Notify();A.Poll();H.Advance(.2)
end
local function Submit(id)
 local ok,why=A.Take(id)
 check(ok==true,'fixture: the Select is submitted: '..tostring(why))
 check(H.perks.pendingSelectSpellId==id,'fixture: the client latch holds it')
end

-- 1. Submission alone is intent.
do
 Boot(30)
 ShowBoard(BOARD)
 local before=Owned(X)
 Submit(X)
 check(Owned(X)==before,'submitting a Select does not change ownership')
 check(A.InFlight()==true,'and the Select is in flight')
end

-- 2. The board is replaced -- the ordinary auto-chain -- and the granted
-- mirror has not moved. Nothing was confirmed.
do
 Boot(30)
 ShowBoard(BOARD)
 check(Owned(X)==0,'fixture: X is not owned')
 Submit(X)
 Resolve(NEXT)
 check(Owned(X)==0,
  'a replaced board does not make an ungranted Select owned: owned='..Owned(X))
 check(A.InFlight()==true,
  'the Select is still unresolved, so it still counts as in flight')
 local ok,why=A.Take(200020)
 check(ok~=true and tostring(why)=='in flight',
  'a second Select is refused while the first is unresolved: '..tostring(why))
 check(select(2,A.Banish(0))=='in flight','so is a Banish')
 check(select(2,A.Freeze(0))=='in flight','and a Freeze')
 check(select(2,A.Reroll())=='in flight','and a Reroll')
 local takes=0
 for _,action in ipairs(H.actions) do if action[1]=='take' then takes=takes+1 end end
 check(takes==1,'only the one Select ever reached the service: '..takes)
end

-- 3. The board disappears.
do
 Boot(30)
 ShowBoard(BOARD)
 Submit(X)
 Resolve(nil)
 check(Owned(X)==0,'a vanished board does not make it owned: owned='..Owned(X))
 check(A.InFlight()==true,'and it stays unresolved')
end

-- 4. Refusal: the latch clears and the same board stays. Nothing was granted
-- and nothing is pending any more.
do
 Boot(30)
 ShowBoard(BOARD)
 Submit(X)
 Resolve('same')
 check(Owned(X)==0,'a refused Select is not owned')
 check(A.InFlight()==false,'and it is released, so the next action may proceed')
end

-- 5. Time passes. Elapsed time is never grant evidence.
-- (a) The latch is held with no reply. The adapter's existing watchdog
-- declares a latch dead after 10 s -- some refusals arrive with no reply at
-- all, and a held latch would otherwise stop automation for the session --
-- and releases it. Released is not granted: it is still not owned.
do
 Boot(30)
 ShowBoard(BOARD)
 Submit(X)
 H.Advance(60)
 check(Owned(X)==0,'a minute with the latch held does not make it owned')
 check(A.InFlight()==false,
  'and the existing no-reply watchdog has released it rather than stall automation')
 Resolve(NEXT)
 check(Owned(X)==0,'a late board change after that still does not make it owned')
end
-- (b) The board moved on and then time passes with no grant. The wait for
-- the grant is not ended by time: the Select stays in flight, so nothing can
-- be picked on the assumption that it was granted.
do
 Boot(30)
 ShowBoard(BOARD)
 Submit(X)
 Resolve(NEXT)
 H.Advance(60)
 check(Owned(X)==0,'a minute after the board moved on does not make it owned: owned='..Owned(X))
 check(A.InFlight()==true,'and the Select is still waiting for its grant')
end

-- 6. A DIFFERENT Echo is granted. That is not this Select's grant.
do
 Boot(30)
 ShowBoard(BOARD)
 Submit(X)
 Resolve(NEXT)
 Grant(Y,1)
 check(Owned(Y)==1,'the other grant is ownership of the other Echo')
 check(Owned(X)==0,'but it does not confirm the pending Select: owned='..Owned(X))
 check(A.InFlight()==true,'which stays unresolved')
end

-- 7. The mirror is replaced by a new table with the same contents. A new
-- reference is not new evidence.
do
 Boot(30)
 ShowBoard(BOARD)
 Submit(X)
 Resolve(NEXT)
 H.granted=H.Clone(H.granted or {});H.Notify();A.Poll();H.Advance(.2)
 check(Owned(X)==0,'a new table with the same contents confirms nothing')
 check(A.InFlight()==true,'and the Select stays unresolved')
end

-- 8. Counts, not just presence: owned once, picked twice this run, granted
-- neither time.
do
 Boot(30,{['Echo 10']={{spellId=X,quality=2}}})
 check(Owned(X)==1,'fixture: X is owned once')
 ShowBoard(BOARD)
 Submit(X)
 Resolve(NEXT)
 check(Owned(X)==1,'an ungranted Select does not raise the count: owned='..Owned(X))
 check(A.InFlight()==true,
  'and the stack already owned is not mistaken for the grant of this Select')
 Grant(X,2)
 check(Owned(X)==2 and A.InFlight()==false,'the second stack, when granted, is')
end

-- 9. The positive control: the same Echo IS granted, a little later. That is
-- the evidence, and it resolves the Select exactly once.
do
 Boot(30)
 ShowBoard(BOARD)
 Submit(X)
 Resolve(NEXT)
 check(Owned(X)==0,'fixture: not owned before the grant arrives')
 Grant(X,2)
 check(Owned(X)==1,'the delayed grant is ownership, counted once: owned='..Owned(X))
 check(A.InFlight()==false,'and it resolves the Select')
 local ok,why=A.Take(200020)
 check(ok==true,'so the next Select may proceed: '..tostring(why))
 Resolve({{spellId=200030,quality=1},{spellId=200031,quality=1},{spellId=200032,quality=1}})
 check(Owned(200020)==0,'and that one too waits for its own grant')
 Grant(200020,1)
 check(Owned(X)==1 and Owned(200020)==1,'each grant is counted once, for its own Echo')
end

-- 10. Reload. A saved profile from an earlier build may still carry the old
-- recordedPicks field; it is kept as data and never read back as ownership.
-- A Select pending at the time of a reload is not ownership afterwards.
-- These are CONTROLS, not regressions: the old code never read the stored
-- field back and kept its picks in memory, so they hold on the parent too.
-- They pin the contract so a later change cannot start reading it back.
do
 Boot(30,nil,function(db) db.chars[F.NAME].recordedPicks={[X]=4} end)
 check(Owned(X)==0,'a stored recordedPicks count is not ownership: owned='..Owned(X))
 check(type(Nexus.Store.State().recordedPicks)=='table'
  and Nexus.Store.State().recordedPicks[X]==4,'and the stored field itself is left as it was')
 ShowBoard(BOARD)
 Submit(X)
 Resolve(NEXT)
 local carried=F.Serialize(NexusDB)
 H=F.Boot(assert(loadstring('return '..carried))(),function(h) h.playerLevel=30 end)
 A=Nexus.GameAdapter;H.Advance(.5)
 check(Owned(X)==0,'after a reload the pending Select is still not owned')
end

-- 11. Save eligibility reads ownership. At level 80 with 78 rolled Echoes, an
-- ungranted 79th Select must not make the run look complete.
do
 local granted,left,id={},78,200040
 while left>0 do
  local n=math.min(5,left);local list={}
  for i=1,n do list[i]={spellId=id,quality=0} end
  granted['Echo '..(id-200000)]=list;left=left-n;id=id+1
 end
 Boot(80,granted)
 check(A.Owned().total==78,'fixture: 78 rolled Echoes: '..tostring(A.Owned().total))
 ShowBoard(BOARD)
 Submit(X)
 Resolve(nil)
 check(A.Owned().total==78,
  'an ungranted 79th Select does not complete the run: total='..tostring(A.Owned().total))
 -- The save gate reads this total (rolledTotal >= 79). A check that no save
 -- happened would prove nothing here: this fixture has autoSave off, so it
 -- holds on the parent as well. The total above is the discriminating fact.
 Grant(X,2)
 check(A.Owned().total==79,'the real grant completes it: total='..tostring(A.Owned().total))
end

-- 12. A run boundary ends the wait. A new run voids the old run's pending
-- Select without granting it, so automation is not held by a run that is
-- over, and nothing from it is owned in the new one.
do
 Boot(30)
 ShowBoard(BOARD)
 Submit(X)
 Resolve(NEXT)
 check(A.InFlight()==true,'fixture: the Select is waiting for its grant')
 A.RunBoundaryReset()
 check(A.InFlight()==false,'a run boundary releases it')
 check(Owned(X)==0,'without making it owned')
end

-- 13. The baseline is the count BEFORE the Select was sent. The grant can
-- land before the latch clears, or in the same poll as the latch clear and
-- the next board. A baseline taken at the board change would already include
-- the grant, the mirror could never rise above it, and automation would stay
-- held for good. Both orders must confirm.
do
 Boot(30)
 ShowBoard(BOARD)
 Submit(X)
 -- The grant arrives while the latch is still held.
 local out=H.Clone(H.granted or {})
 out['Echo 10']=out['Echo 10'] or {}
 table.insert(out['Echo 10'],{spellId=X,quality=2})
 H.granted=out
 Resolve(NEXT)
 check(Owned(X)==1,'a grant that lands before the latch clears is owned')
 check(A.InFlight()==false,'and it confirms the Select')
end
do
 Boot(30)
 ShowBoard(BOARD)
 Submit(X)
 -- Grant, latch clear and next board, all before the adapter next polls.
 local out=H.Clone(H.granted or {})
 out['Echo 10']=out['Echo 10'] or {}
 table.insert(out['Echo 10'],{spellId=X,quality=2})
 H.granted=out
 H.perks.pendingSelectSpellId=nil
 H.perks.currentChoice=H.Clone(NEXT)
 H.Notify();A.Poll();H.Advance(.2)
 check(Owned(X)==1,'a grant in the same poll as the board change is owned')
 check(A.InFlight()==false,'and it confirms the Select in that same poll')
end

-- 14. The real runtime, with Ordinary Automation on and a Wishlist that wants
-- three copies of one Echo. Automation takes the first copy. The board is
-- replaced by one that offers the same Echo again, and the mirror has not
-- moved. Before #62 the runtime took it again on the strength of intent; now
-- it waits. When the grant lands -- with no forced recompute -- the lock
-- step, deferred throughout, runs to completion, and the next board that
-- offers the Echo is taken.
do
 -- A clean profile: the earlier sections' saved variables (autoPick off)
 -- must not leak into this boot.
 Nexus=nil;SlashCmdList=nil;NexusDB=nil;WishlistRealizerDB=nil
 H=dofile('tests/prototype/harness.lua');H.pendingRolls=40;H.playerLevel=30;H.Boot()
 A=Nexus.GameAdapter
 local W=200001
 A.SetFirstLoadoutWishlistIdentity('Synthetic three copies',{{spellId=W,quality=1,stacks=3}})
 SlashCmdList.NEXUS('reroll off');SlashCmdList.NEXUS('freeze off');SlashCmdList.NEXUS('banish off')
 Nexus.Store.Settings().autoLockEchoes=true
 local function Takes(id)
  id=id or W
  local n=0
  for _,action in ipairs(H.actions) do if action[1]=='take' and action[2]==id then n=n+1 end end
  return n
 end
 local function Deferred()
  local trace=Nexus.GetDiagnosticPageText('autolock') or ''
  return trace:find('deferred: an Echo action is still in flight',1,true)~=nil
 end
 H.Board({{spellId=W,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}})
 H.Notify();H.Advance(.5)
 SlashCmdList.NEXUS('auto');H.Advance(2)
 check(Takes()==1,'fixture: automation takes the first wished copy: '..Takes())
 -- The server accepts: the latch clears and the next board offers it again.
 H.perks.pendingSelectSpellId=nil
 H.Board({{spellId=W,quality=1},{spellId=200022,quality=0},{spellId=200023,quality=1}})
 H.Notify();H.Advance(5)
 check(Takes()==1,
  'automation does not take it again while the first copy awaits its grant: '..Takes())
 check(A.InFlight()==true and Owned(W)==0,'the Select is waiting, and not owned')
 -- Data changes mid-wait -- here, another Echo is granted -- which makes the
 -- lock step due. It must defer, and the other grant must confirm nothing.
 do
  local other=H.Clone(H.granted or {})
  other['Echo 30']=other['Echo 30'] or {}
  table.insert(other['Echo 30'],{spellId=200030,quality=1})
  H.granted=other;H.Notify();H.Advance(1)
 end
 check(Deferred(),'the lock step, due on that change, defers while the Select waits')
 check(A.InFlight()==true and Owned(W)==0 and Takes()==1,
  'the other grant confirms nothing, and nothing is taken on intent')
 -- The grant lands with a next board that does not offer the Echo. Nothing
 -- forces a step.
 local out=H.Clone(H.granted or {})
 out['Echo 1']=out['Echo 1'] or {}
 table.insert(out['Echo 1'],{spellId=W,quality=1})
 H.granted=out
 H.Board({{spellId=200024,quality=0},{spellId=200025,quality=1},{spellId=200026,quality=0}})
 H.Notify();H.Advance(3)
 check(Owned(W)==1,'the grant is ownership, counted once: '..Owned(W))
 -- The fixture has no lock target, so the lock step's own trace is the
 -- evidence, not lock actions.
 check(not Deferred(),'the deferred lock step has run to completion')
 check(Takes(200024)==1,
  'automation acts again -- it takes from the new board -- so the wait is released: '..Takes(200024))
 -- That Select is intent too. Once it is granted, the next board that
 -- offers the wished Echo is taken.
 H.perks.pendingSelectSpellId=nil
 out=H.Clone(H.granted)
 out['Echo 2']=out['Echo 2'] or {}
 table.insert(out['Echo 2'],{spellId=200024,quality=0})
 H.granted=out
 H.Board({{spellId=W,quality=1},{spellId=200027,quality=0},{spellId=200028,quality=1}})
 H.Notify();H.Advance(2)
 check(Takes()==2,'and automation takes the next wished copy it is offered: '..Takes())
end

-- 15. A lock step deferred during a Banish latch runs again once the latch
-- clears. A latch clearing marks only the board dirty, which on its own does
-- not bring the lock step round again; without the re-check the deferred
-- step was dropped until some unrelated data change.
do
 -- A clean profile: the earlier sections' saved variables (autoPick off)
 -- must not leak into this boot.
 Nexus=nil;SlashCmdList=nil;NexusDB=nil;WishlistRealizerDB=nil
 H=dofile('tests/prototype/harness.lua');H.pendingRolls=40;H.playerLevel=30;H.Boot()
 A=Nexus.GameAdapter
 Nexus.Store.Settings().autoLockEchoes=true
 SlashCmdList.NEXUS('auto')
 H.Board({{spellId=200010,quality=2},{spellId=200011,quality=1},{spellId=200012,quality=0}})
 H.Notify();H.Advance(.5)
 local function Deferred()
  local trace=Nexus.GetDiagnosticPageText('autolock') or ''
  return trace:find('deferred: an Echo action is still in flight',1,true)~=nil
 end
 H.perks.pendingBanishIndex=0
 Nexus.RequestRecompute();H.Advance(.5)
 check(Deferred(),'fixture: the lock step deferred while the Banish latch was held')
 H.perks.pendingBanishIndex=nil
 H.Notify();A.Poll();H.Advance(2.5)
 check(not Deferred(),'the lock step runs again once the latch clears')
end

-- 16. The grant lands while the Select latch is still held, so the poll that
-- confirms the Select sees no change in the mirror. The confirmation itself
-- must make the deferred lock step due; the one-second re-check alone would
-- run it late.
do
 Nexus=nil;SlashCmdList=nil;NexusDB=nil;WishlistRealizerDB=nil
 H=dofile('tests/prototype/harness.lua');H.pendingRolls=40;H.playerLevel=30;H.Boot()
 A=Nexus.GameAdapter
 local W=200001
 A.SetFirstLoadoutWishlistIdentity('Synthetic three copies',{{spellId=W,quality=1,stacks=3}})
 SlashCmdList.NEXUS('reroll off');SlashCmdList.NEXUS('freeze off');SlashCmdList.NEXUS('banish off')
 Nexus.Store.Settings().autoLockEchoes=true
 local function Deferred()
  local trace=Nexus.GetDiagnosticPageText('autolock') or ''
  return trace:find('deferred: an Echo action is still in flight',1,true)~=nil
 end
 H.Board({{spellId=W,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}})
 H.Notify();H.Advance(.5)
 SlashCmdList.NEXUS('auto');H.Advance(2)
 local out=H.Clone(H.granted or {})
 out['Echo 1']=out['Echo 1'] or {}
 table.insert(out['Echo 1'],{spellId=W,quality=1})
 H.granted=out;H.Notify();H.Advance(3)
 check(Deferred() and A.InFlight(),'fixture: the lock step defers while the Select latch is held')
 H.perks.pendingSelectSpellId=nil
 H.Board({{spellId=200024,quality=0},{spellId=200025,quality=1},{spellId=200026,quality=0}})
 H.Notify();H.Advance(.3)
 check(not A.InFlight() and Owned(W)==1,'the latch clears, and the grant already seen confirms the Select')
 check(not Deferred(),'and the confirmation makes the lock step due at once')
end

print('PASS select_intent_ownership: a submitted Select is intent until the granted mirror shows it checks='..checks)
