-- Client-side latency between already-safe Echo actions, and the safety of the early poll.
--
-- Simulated clock (harness), 60 frames per second, a mocked server that answers each accepted
-- action after a fixed round trip with the next scripted board. NOT a WoW client and NOT a
-- server measurement: it shows what the ADDON adds between a reply and the next send.
--
-- Hypothesis: the runtime loop only polls on a 0.2 s tick, so every reply and every deadline
-- waits up to 0.2 s for the next tick. The early poll (AutomationRuntime.RunUpdate) runs the
-- same poll at once when the client reports a board or Echo-data notification, or a scheduled
-- step is due. The 0.4 s intent beat, the in-flight and grant holds and every authorization
-- check are untouched; this test pins that they still hold exactly.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local FPS=60;local DT=1/FPS

local function Boot(early)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/harness.lua');H.pendingRolls=400;H.Boot()
 H.run.totalRerolls,H.run.remainingBanishes,H.run.totalFreezes=900,900,900
 if early==false then Nexus.EarlyPollDisabled=true end
 assert(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity('Latency',{{spellId=200001,quality=1,stacks=3},{spellId=200002,quality=2,stacks=3}}))
 return H
end
local function Step(H,seconds) H.Advance(seconds,DT) end

-- Scripted run: unwanted boards with a wanted offer every 7th board. Returns the actions, the
-- time of each send, each intent's preparedAt, and the reply times.
local function Script(early,rtt,count)
 local H=Boot(early)
 local n=0
 local function NextBoard(frozenIndex)
  n=n+1
  local base=200100+(n*3)%80
  local cards={{spellId=base,quality=0},{spellId=base+1,quality=1},{spellId=base+2,quality=0}}
  if n%7==0 then cards[2]={spellId=200001,quality=1} end
  if frozenIndex then cards[frozenIndex].isFrozen=true end
  return cards
 end
 H.Board(NextBoard());H.Notify();Step(H,.5)
 SlashCmdList.NEXUS('auto')
 local sent,prepared,submitted,replies,seen,pending={}, {}, {}, {}, #H.actions,nil
 local limit=H.now+count*(rtt+2)
 while #sent<count and H.now<limit do
  Step(H,DT)
  if #H.actions>seen then
   local l=Nexus.RecomputeStats().lastActionLifecycle
   for i=seen+1,#H.actions do sent[#sent+1]=H.now;prepared[#sent]=l.preparedAt;submitted[#sent]=l.submittedAt end
   local last=H.actions[#H.actions]
   pending={at=H.now+rtt,kind=last[1],index=last[2],spell=last[2]}
   seen=#H.actions
  end
  if pending and H.now>=pending.at then
   local k=pending;pending=nil
   H.perks.pendingSelectSpellId,H.perks.pendingBanishIndex,H.perks.pendingFreezeIndex,H.perks.pendingReroll=nil,nil,nil,nil
   if k.kind=='take' and H.names[k.spell] then
    H.granted[H.names[k.spell]]=H.granted[H.names[k.spell]] or {}
    table.insert(H.granted[H.names[k.spell]],{spellId=k.spell,quality=H.db[k.spell].quality})
   end
   H.Board(NextBoard(k.kind=='freeze' and (k.index+1) or nil));H.Notify()
   replies[#sent]=H.now
  end
 end
 local actions={};for i,a in ipairs(H.actions)do actions[i]=a[1]..':'..tostring(a[2]) end
 return {H=H,sent=sent,prepared=prepared,submitted=submitted,replies=replies,actions=actions}
end

-- 1. The same script with and without the early poll: identical actions, never slower, faster on average.
local COUNT=30
for _,rtt in ipairs({0.05,0.12,0.30})do
 local base,fast=Script(false,rtt,COUNT),Script(true,rtt,COUNT)
 check(#base.sent==COUNT and #fast.sent==COUNT,'both runs sent '..COUNT..' actions at RTT '..rtt)
 for i=1,COUNT do check(base.actions[i]==fast.actions[i],'RTT '..rtt..': action '..i..' is the same with and without the early poll: '..base.actions[i]..' / '..fast.actions[i]) end
 local saved,worse=0,0
 for i=2,COUNT do
  local before,after=base.sent[i]-base.sent[i-1],fast.sent[i]-fast.sent[i-1]
  saved=saved+(before-after)
  if after>before+1e-6 then worse=worse+1 end
 end
 check(worse==0,'RTT '..rtt..': no cycle is slower with the early poll')
 local meanSaved=saved/(COUNT-1)
 check(meanSaved>=0.04,string.format('RTT %.2f: the early poll saves at least 0.04 s per action: %.3f',rtt,meanSaved))
 -- Beat: every action is sent at least 0.4 s after its intent was prepared, early poll or not.
 for i=1,COUNT do
  check(fast.submitted[i]-fast.prepared[i]>=0.4-1e-6,string.format('RTT %.2f action %d: the 0.4 s intent beat is kept (%.3f)',rtt,i,fast.submitted[i]-fast.prepared[i]))
 end
 -- The client delay (reply -> next send) is the beat plus frame granularity.
 local worst=0
 for i=2,COUNT do if fast.replies[i-1] then local d=fast.sent[i]-fast.replies[i-1];if d>worst then worst=d end end end
 check(worst<=0.4+4*DT,string.format('RTT %.2f: the client delay after a reply is the beat plus a few frames, with no tick wait: %.3f',rtt,worst))
 print(string.format('LATENCY RTT %.2f: cycle before %.3f -> after %.3f (mean saved %.3f s per action; same %d actions)',rtt,
  (base.sent[COUNT]-base.sent[1])/(COUNT-1),(fast.sent[COUNT]-fast.sent[1])/(COUNT-1),meanSaved,COUNT))
end

-- 2. A board notification does not release an action while the client latch is still set.
do
 local H=Boot(true)
 H.Board({{spellId=200100,quality=0},{spellId=200101,quality=1},{spellId=200102,quality=0}});H.Notify();Step(H,.5)
 SlashCmdList.NEXUS('auto');Step(H,1.2)
 check(#H.actions==1,'precondition: one action is in flight: '..#H.actions)
 local latch=H.perks.pendingBanishIndex or H.perks.pendingReroll
 check(latch~=nil,'precondition: the client latch is set')
 for i=1,12 do
  H.Board({{spellId=200110+i,quality=0},{spellId=200120+i,quality=1},{spellId=200130+i,quality=0}});Step(H,.25)
 end
 check(#H.actions==1,'new boards shown while the latch is still set release nothing: '..#H.actions)
 H.perks.pendingBanishIndex,H.perks.pendingReroll=nil,nil
 H.Board({{spellId=200200,quality=0},{spellId=200201,quality=1},{spellId=200202,quality=0}});H.Notify();Step(H,1)
 check(#H.actions==2,'once the latch clears the next action follows: '..#H.actions)
end

-- 3. A Take is not complete until its grant is seen: elapsed time and a new board are not completion.
-- The grant arrives at several phases of the 0.2 s grid; the Echo-data notification wakes the loop at
-- once at every phase, and nothing is sent before the grant is observed.
for _,offset in ipairs({0,0.03,0.06,0.09,0.12,0.15,0.18})do
 local H=Boot(true)
 H.Board({{spellId=200001,quality=1},{spellId=200100,quality=0},{spellId=200101,quality=0}});H.Notify();Step(H,.5)
 SlashCmdList.NEXUS('auto');Step(H,1.2)
 check(H.actions[1] and H.actions[1][1]=='take' and H.actions[1][2]==200001,'precondition: the wanted offer is taken: '..tostring(H.actions[1] and H.actions[1][1]))
 H.perks.pendingSelectSpellId=nil
 H.Board({{spellId=200110,quality=0},{spellId=200111,quality=1},{spellId=200112,quality=0}});H.Notify();Step(H,6+offset)
 check(#H.actions==1,'a new board and six seconds without a grant start no action: '..#H.actions)
 H.granted[H.names[200001]]={{spellId=200001,quality=1}}
 H.Notify();local tGrant=H.now
 local guard=0
 while #H.actions<2 and guard<400 do Step(H,DT);guard=guard+1 end
 check(#H.actions>=2,'once the grant is observed the next action follows: '..#H.actions)
 -- The decision was already waiting (its beat is long over): only the grant gate held it. The
 -- notification releases it within a few frames, not up to a tick later.
 check(H.now-tGrant<=3*DT,string.format('offset %.2f: the Echo-data notification wakes the loop: the waiting action follows within three frames (%.3f s)',offset,H.now-tGrant))
end

-- 3b. A notification in the middle of the beat moves the poll grid; the due beat still wakes the loop.
for _,offset in ipairs({0.03,0.06,0.09,0.12,0.15})do
 local H=Boot(true)
 H.Board({{spellId=200100,quality=0},{spellId=200101,quality=1},{spellId=200102,quality=0}});H.Notify();Step(H,.5)
 SlashCmdList.NEXUS('auto');Step(H,1.2)
 H.perks.pendingSelectSpellId,H.perks.pendingBanishIndex,H.perks.pendingFreezeIndex,H.perks.pendingReroll=nil,nil,nil,nil
 local sent=#H.actions
 H.Board({{spellId=200200,quality=0},{spellId=200201,quality=1},{spellId=200202,quality=0}});H.Notify();local t0=H.now
 local stirred=false
 local guard=0
 while #H.actions==sent and guard<400 do
  Step(H,DT);guard=guard+1
  if not stirred and H.now-t0>=offset then stirred=true;H.Notify() end
 end
 check(#H.actions==sent+1,'the next action is sent')
 check(H.now-t0<=0.4+4*DT,string.format('offset %.2f: a notification during the beat does not delay the send (%.3f s)',offset,H.now-t0))
end

-- 4. The beat is kept when the notification arrives at once.
do
 local H=Boot(true)
 H.Board({{spellId=200100,quality=0},{spellId=200101,quality=1},{spellId=200102,quality=0}});H.Notify();Step(H,.5)
 SlashCmdList.NEXUS('auto')
 local t=H.now
 Step(H,.35)
 check(#H.actions==0,'nothing is sent inside the 0.4 s intent beat: '..#H.actions)
 Step(H,.5)
 check(#H.actions==1,'the action follows once the beat is over')
end

-- 5. Auto OFF: no early poll, no action.
do
 local H=Boot(true)
 H.Board({{spellId=200100,quality=0},{spellId=200101,quality=1},{spellId=200102,quality=0}});H.Notify();Step(H,.5)
 local before=Nexus.RecomputeStats().earlyPolls or 0
 for i=1,40 do H.Board({{spellId=200110+i,quality=0},{spellId=200120+i,quality=1},{spellId=200130+i,quality=0}});Step(H,.1) end
 check((Nexus.RecomputeStats().earlyPolls or 0)==before and #H.actions==0,'Auto OFF: notifications cause no early poll and no action')
end

-- 6. Bounded overhead: an event storm, an idle run and a failing poll.
do
 local H=Boot(true)
 H.Board({{spellId=200100,quality=0},{spellId=200101,quality=1},{spellId=200102,quality=0}});H.Notify();Step(H,.5)
 SlashCmdList.NEXUS('auto');Step(H,.1)
 H.run.totalRerolls,H.run.remainingBanishes,H.run.totalFreezes=0,0,0
 local s0=Nexus.RecomputeStats();local p0,e0=s0.polls,s0.earlyPolls or 0
 for i=1,2*FPS do H.perks.currentChoice=H.perks.currentChoice;H.Board({{spellId=200100,quality=0},{spellId=200101+i%5,quality=1},{spellId=200102,quality=0}});Step(H,DT) end
 local s1=Nexus.RecomputeStats()
 check(s1.polls-p0<=2/0.05+2,'a notification storm (one per frame for 2 s) runs at most one poll per 0.05 s: '..(s1.polls-p0))
 check((s1.earlyPolls or 0)-e0<=2/0.05+2,'early polls in the storm are bounded: '..((s1.earlyPolls or 0)-e0))
 local function Idle(early)
  local H2=Boot(early)
  H2.Board({{spellId=200100,quality=0},{spellId=200101,quality=1},{spellId=200102,quality=0}});H2.Notify();Step(H2,.5)
  SlashCmdList.NEXUS('auto');H2.run.totalRerolls,H2.run.remainingBanishes,H2.run.totalFreezes=0,0,0;Step(H2,3)
  local a=Nexus.RecomputeStats();local pa,ea=a.polls,a.earlyPolls or 0
  Step(H2,10)
  local b=Nexus.RecomputeStats()
  return b.polls-pa,(b.earlyPolls or 0)-ea
 end
 local idleOn,idleEarly=Idle(true)
 local idleOff=Idle(false)
 check(math.abs(idleOn-idleOff)<=1,'an idle Auto-ON loop polls as often as before: '..idleOn..' with, '..idleOff..' without the early poll (10 s)')
 check(idleEarly<=2,'an idle loop makes no early poll: '..idleEarly)
 -- A failing poll is not retried early.
 local H3=Boot(true)
 H3.Board({{spellId=200100,quality=0},{spellId=200101,quality=1},{spellId=200102,quality=0}});H3.Notify();Step(H3,.5)
 SlashCmdList.NEXUS('auto');Step(H3,.1)
 local realPoll=Nexus.GameAdapter.Poll
 Nexus.GameAdapter.Poll=function() error('simulated poll failure') end
 local f0=Nexus.RecomputeStats().pollFailures
 for i=1,2*FPS do H3.Board({{spellId=200100,quality=0},{spellId=200101+i%5,quality=1},{spellId=200102,quality=0}});Step(H3,DT) end
 local failures=Nexus.RecomputeStats().pollFailures-f0
 Nexus.GameAdapter.Poll=realPoll
 check(failures<=11,'a failing poll stays on the 0.2 s cadence (10 in 2 s expected): '..failures)
end

-- 7. The knob restores the old timing exactly.
do
 local a,b=Script(false,0.12,12),Script(false,0.12,12)
 for i=1,12 do check(math.abs(a.sent[i]-b.sent[i])<1e-9,'the disabled mode is deterministic') end
 check(a.sent[3]-a.sent[2]>=0.64,'with the early poll disabled the baseline cycle is the old 0.65 s: '..(a.sent[3]-a.sent[2]))
end
print('PASS rolling latency checks='..checks)
