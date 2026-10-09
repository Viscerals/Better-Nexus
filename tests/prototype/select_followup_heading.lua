-- Review F3: Auto ON must not read as acting while an effective wait holds it.
-- The HUD heading names the wait, not "Active", for: an uncertain and then an
-- expired automatic Freeze on the same board (the adapter holds nothing), a
-- refused automatic Take, a player's unanswered Select flag, and the flag of
-- an own Select a run boundary voided. At level 80 with no board, an overdue
-- own Select gives the idle HUD a memory-only effective state (Auto tooltip)
-- and a status that names its wait instead of "finishing final Echo
-- selections". Controls: a normal decision beat and a confirmed result read as
-- active; the exact grant ends the level-80 wait. Real modules, synthetic
-- service.
local F=dofile('tests/prototype/select_followup_support.lua')
local R=F.R
local scenario,finish=R.Checks()

local function Waiting(H,label)
 local e=Nexus.AutomationEffectiveState()
 assert(e.selected==true and e.state=='waiting','setup: '..label..': the effective state is a wait: '..tostring(e.state)..' / '..tostring(e.reason))
end

scenario('an uncertain, then expired, automatic Freeze reads as waiting',function(check)
 local H,A=R.Boot();Nexus.Panel.Show();H.Offer(F.TWO);SlashCmdList.NEXUS('auto')
 local l
 for _=1,20 do H.Advance(.05);l=F.Lifecycle();if l.state=='prepared' then break end end
 assert(l.state=='prepared' and H.boardAttempts==0,'setup: a decision is prepared, nothing sent')
 check(F.Head():find('Active',1,true)~=nil,'control: a normal decision beat reads as active: '..F.Head())
 for _=1,40 do H.Advance(.05);if H.boardAttempts>0 then break end end
 assert(H.boardAttempts==1 and H.perks.pendingFreezeIndex==0,'setup: Auto froze the first of two needed offers')
 H.perks.pendingFreezeIndex=nil;H.Notify();H.Advance(1)
 assert(Nexus.PendingIntentState()=='uncertain' and not A.InFlight(),'setup: uncertain on the same board; the adapter holds nothing')
 Waiting(H,'uncertain Freeze')
 local waits,head=F.HeadWaits()
 check(waits,'an uncertain Freeze: the heading names the wait, not active: '..head)
 H.Advance(10)
 assert(Nexus.PendingIntentState()=='expired','setup: the Freeze expired on the same board')
 Waiting(H,'expired Freeze')
 waits,head=F.HeadWaits()
 check(waits,'an expired Freeze: the heading names the wait, not active: '..head)
 check(H.boardAttempts==1,'nothing else is sent while it waits')
 local frozen=H.Clone(F.TWO);frozen[1].isFrozen=true
 H.perks.pendingFreezeIndex=nil;H.Offer(frozen);H.Advance(.3)
 check(F.Head():find('Active',1,true)~=nil,'control: once a board change answers it, the heading reads as active again: '..F.Head())
end)

scenario('a refused automatic Take reads as waiting',function(check)
 local H,A=R.Boot();Nexus.Panel.Show();H.Offer()
 local calls=0
 H.service.SelectPerk=function() calls=calls+1;return false end -- the client refuses
 SlashCmdList.NEXUS('auto');H.Advance(1.5)
 local l=F.Lifecycle()
 assert(calls==1 and l.actionType=='take' and l.state=='rejected','setup: one automatic Take, refused: '..tostring(l.state))
 Waiting(H,'refused Take')
 local waits,head=F.HeadWaits()
 check(waits,'a refused Take: the heading names the wait, not active: '..head)
 H.Advance(5)
 check(calls==1,'the refused Take is not retried on the same board')
end)

scenario('a player Select flag with no result reads as waiting',function(check)
 local H,A=R.Boot();Nexus.Panel.Show();H.Offer()
 H.perks.pendingSelectSpellId=R.Z -- the player's own Select, unanswered
 SlashCmdList.NEXUS('auto');H.Advance(4)
 assert(H.boardAttempts==0 and A.InFlight() and A.SelectUnresolved()==nil,'setup: the player flag holds the board; nothing sent')
 Waiting(H,'player flag')
 local waits,head=F.HeadWaits()
 check(waits,'a player Select flag: the heading names the wait, not active: '..head)
end)

scenario('the still-set flag of an own Select a run boundary voided reads as waiting',function(check)
 local H,A=R.Boot();Nexus.Panel.Show();R.AutoSubmit(H)
 H.playerLevel=80;H.Advance(1);H.playerLevel=66;H.Advance(2)
 local outcomes=A.SelectRecoveryFacts().outcomes
 local last=outcomes[#outcomes]
 assert(A.SelectUnresolved()==nil and last and last.outcome=='voided','setup: the run boundary voided the own Select')
 assert(H.perks.pendingSelectSpellId==R.X and A.InFlight(),'setup: its client flag is still set and the adapter holds')
 Waiting(H,'voided Select flag')
 local waits,head=F.HeadWaits()
 check(waits,'a voided Select flag: the heading names the wait, not active: '..head)
 check(H.boardAttempts==1,'nothing new is sent')
end)

scenario('level 80 with no board: an overdue own Select has a memory-only effective state and a truthful wait',function(check)
 local H,A=R.Boot();H.playerLevel=80;Nexus.Panel.Show();R.AutoSubmit(H)
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;H.Notify();H.Advance(12)
 local ordinal,phase,_,_,_,overdue=A.SelectUnresolved()
 assert(ordinal==1 and phase=='grant' and overdue and A.Board()==nil,'setup: level 80, no board, the own Select overdue')
 local e=Nexus.AutomationEffectiveState()
 assert(e.state=='waiting' or e.state=='rechecking','setup: the effective state names the wait: '..tostring(e.state))
 local status=H.runtime.StatusLine()
 check(not status:find('finishing final Echo selections',1,true) and F.SameWait(status,e.reason),
  'the status names the unresolved Select wait: '..status)
 local calls,reads,ok,now=F.Passive(A,F.NowLine)
 check(ok and #calls==0 and reads==0,'the Auto tooltip reads memory only: '..table.concat(calls,',')..' reads='..reads..' '..tostring(ok or now))
 check(ok and now~=nil and (now:find('waiting',1,true)~=nil or now:find('rechecking',1,true)~=nil),
  'the idle HUD carries the effective wait to the Auto tooltip: '..tostring(now))
 check(H.boardAttempts==1 and H.Auto(),'nothing is resent; Auto stays selected')
 R.Grant(H,R.X);H.Advance(1)
 check(A.SelectOutcome(1)=='proven' and not A.InFlight() and not F.SameWait(H.runtime.StatusLine(),e.reason),
  'control: the exact grant ends the wait and its text: '..H.runtime.StatusLine())
end)
finish()
