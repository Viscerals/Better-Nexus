-- Review F8: the runtime's lifecycle of a tracked automatic Take must agree
-- with the adapter's record of its Select. A board that moves on or clears
-- without that Select's exact grant leaves the Take uncertain in the lifecycle
-- and the roll record, never confirmed. Its exact grant with the client flag
-- cleared -- on a moved or on the same board -- is confirmed:grant_observed.
-- Control: a Freeze answered by its board change keeps confirmed:
-- board_transition. Auto is turned OFF right after the submission, so no later
-- decision replaces the lifecycle being read. Real modules, synthetic service.
local F=dofile('tests/prototype/select_followup_support.lua')
local R=F.R
local scenario,finish=R.Checks()

local function Submitted()
 local H,A=R.Boot();R.AutoSubmit(H)
 SlashCmdList.NEXUS('auto')
 local l,counts=F.Lifecycle()
 assert(not H.Auto() and l.actionType=='take' and l.state=='submitted','setup: one automatic Take submitted, then Auto OFF')
 return H,A,counts.confirmed
end

local function Unconfirmed(name,answer)
 scenario(name,function(check)
  local H,A,confirmed=Submitted()
  answer(H);H.Advance(1)
  assert(A.SelectOutcome(1)=='unresolved' and A.InFlight(),'setup: the adapter keeps the Select unresolved')
  local l,counts=F.Lifecycle()
  check(l.actionType=='take' and l.state=='uncertain','the Take stays uncertain: '..tostring(l.state)..'/'..tostring(l.reason))
  check(counts.confirmed==confirmed,'nothing is counted as confirmed')
  local io=F.TraceIo()
  check(io:find('uncertain:',1,true)~=nil and not io:find('confirmed:',1,true),'the roll record has no confirmation: '..io)
 end)
end
Unconfirmed('a board that moves on without the exact grant leaves the Take uncertain',function(H)
 H.perks.pendingSelectSpellId=nil;H.Offer(R.next) end)
Unconfirmed('a board that clears without the exact grant leaves the Take uncertain',function(H)
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;H.Notify() end)

local function Granted(name,answer)
 scenario(name,function(check)
  local H,A=Submitted()
  R.Grant(H,R.X);H.perks.pendingSelectSpellId=nil;answer(H);H.Advance(1)
  assert(A.SelectOutcome(1)=='proven' and not A.InFlight(),'setup: the adapter proved the exact grant')
  local l=F.Lifecycle()
  check(l.actionType=='take' and l.state=='confirmed' and l.reason=='grant_observed',
   'the exact grant is the observed result: '..tostring(l.state)..'/'..tostring(l.reason))
  check(F.TraceIo():find('confirmed:grant_observed',1,true)~=nil,'the roll record names the observed grant: '..F.TraceIo())
  check(H.Count()==1 and (A.Owned().bySpell[R.X] or 0)==1,'counted once; nothing resent')
 end)
end
Granted('the exact grant with the flag cleared and the board moved on is grant_observed',function(H) H.Offer(R.next) end)
Granted('the exact grant with the flag cleared on the same board is grant_observed',function(H) H.Notify();Nexus.GameAdapter.Poll() end)

scenario('control: a Freeze answered by its board change stays confirmed:board_transition',function(check)
 local H,A=R.Boot();H.Offer(F.TWO);SlashCmdList.NEXUS('auto')
 for _=1,40 do H.Advance(.05);if H.boardAttempts>0 then break end end
 local l=F.Lifecycle()
 assert(H.boardAttempts==1 and l.actionType=='freeze' and l.state=='submitted','setup: one automatic Freeze submitted')
 SlashCmdList.NEXUS('auto')
 local frozen=H.Clone(F.TWO);frozen[1].isFrozen=true
 H.perks.pendingFreezeIndex=nil;H.Offer(frozen);H.Advance(1)
 l=F.Lifecycle()
 check(l.actionType=='freeze' and l.state=='confirmed' and l.reason=='board_transition',
  'a non-Select confirmation keeps its guarantee: '..tostring(l.state)..'/'..tostring(l.reason))
end)
finish()
