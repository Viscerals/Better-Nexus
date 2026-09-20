-- Deferred inbound admission must not starve outbound control. The user's
-- explicit Sync Now request goes through the real slash command, session,
-- lifecycle readiness gate, transport pacing and catalog while valid inbound
-- summaries wait for admission. Nothing here suppresses or fabricates traffic.
local S=dofile('tests/prototype/sync_admission_support.lua');local T=S.T
local function Deferred()return Nexus.Sync.WorkState().deferredAdmissions end
local function Requests(H)
 local n=0
 for _,packet in ipairs(H.sent)do
  if packet.text:gsub('||','|'):gsub('^P%d+:',''):match('^WLRQ|')then n=n+1 end
 end
 return n
end
local function Pressure(count,prefix)
 -- Valid summaries from several verified owners, within the per-sender bound.
 for i=1,count do S.Receive(prefix..i,'Peer'..((i-1)%4+1),S.base+i,'Queue pressure '..i)end
end

local function Committed(C,prefix)
 local n=0;for i=1,40 do if C.Get(prefix..i)then n=n+1 end end;return n
end
-- 0. Control: the same pressure with no outbound request. This is the rate the
-- ordinary one-slice catalog admits deferred items before their fixed deadline.
local H,C=S.Boot(20);S.Hold(C)
Pressure(40,'fair-a-')
T.Until(H,function()return Deferred()==0 and C.ManualPreparationStatus().ready end,60000)
local control=Committed(C,'fair-a-')
assert(control>0 and Requests(H)==0,'control admits deferred items and sends no request')
print('CONTROL no outbound request: '..control..' of 40 deferred items committed before the fixed deadline')

-- 1. A manual request is sent while deferred work is still waiting.
H,C=S.Boot(20);S.Hold(C)
-- Observe only: every real transmission with its time and the admissions so far.
local sends={};local send=SendChatMessage
SendChatMessage=function(text,...)
 sends[#sends+1]={t=H.now,resolved=Nexus.Sync.Stats().admissionResolved,deferred=Deferred(),text=text}
 return send(text,...)
end
Pressure(40,'fair-a-')
local enqueuedAt=H.now
assert(Deferred()==40,'fixture: forty valid inbound items wait for admission')
local before=Requests(H)
H.Advance(7,.05)
SlashCmdList.NEXUS('sync')
local started,resolvedAtClick=H.now,Nexus.Sync.Stats().admissionResolved
local sentAt,deferredAtSend,resolvedAtSend
T.Until(H,function()
 if not sentAt and Requests(H)>before then
  sentAt,deferredAtSend,resolvedAtSend=H.now,Deferred(),Nexus.Sync.Stats().admissionResolved
 end
 return sentAt~=nil or Deferred()==0 or H.now-started>=300
end,40000)
resolvedAtSend=resolvedAtSend or Nexus.Sync.Stats().admissionResolved
local servedFirst=resolvedAtSend-resolvedAtClick
print(string.format('OBSERVED request_sent=%s after=%.1fs deferred_items_admitted_before_the_request=%d deferred_at_send=%s expired=%d terminal=%s queue=%s',
 tostring(sentAt~=nil),(sentAt or H.now)-started,servedFirst,tostring(deferredAtSend),
 Nexus.Sync.Stats().admissionExpired,tostring(Nexus.Sync.Stats().terminalReason),tostring(Nexus.Sync.Stats().queueOutcome)))
assert(sentAt~=nil,'the explicit Sync Now request is transmitted')
-- Fair progress: the request may wait for the one catalog transaction that is
-- already in flight and for one more turn. It must not wait behind the queue.
-- On 8ab9fc2 this count was 8 to 40.
assert(servedFirst<=2 and deferredAtSend>=30,'an explicit Sync Now request is not starved behind deferred inbound admissions: '..servedFirst..' were admitted first, '..tostring(deferredAtSend)..' still waited')
assert(Requests(H)==before+1,'exactly one request was transmitted')

-- 2. Deferred valid inbound work still progresses after the send: fair both ways.
T.Until(H,function()return Deferred()==0 end,60000)
-- The queue is empty no later than the fixed per-item deadline, measured from
-- arrival. The last accepted transaction may still be committing after that.
local drainedAfter=H.now-enqueuedAt
T.Until(H,function()return C.ManualPreparationStatus().ready end,60000)
local stats=Nexus.Sync.Stats()
assert(stats.admissionResolved>resolvedAtSend,'deferred items keep being admitted after the request was sent')
assert(stats.admissionResolved+stats.admissionExpired+stats.admissionCancelled+stats.admissionSuperseded==40,'every retained item reached exactly one terminal state')
local committed=Committed(C,'fair-a-')
for i=1,40 do if C.Get('fair-a-'..i)then assert(H.puts['fair-a-'..i].accepted==1,'one submission per committed item')end end
assert(committed==stats.admissionResolved and committed>0,'each resolved item is a real committed row; none is fabricated')
-- Yielding to outbound traffic must not cost inbound work its progress: the
-- same number commits as with no outbound traffic at all, within two turns.
assert(committed>=control-2,'deferred inbound work keeps its ordinary progress beside outbound traffic: '..committed..' committed, control '..control)
assert(stats.admissionYielded>0,'fixture: admission did yield to owed outbound traffic')
assert(stats.malformedRejected==0,'valid inbound items were never reclassified as malformed')
print('PASS manual request sent under deferred pressure; '..committed..' deferred items committed, '..stats.admissionExpired..' expired')

-- 3. Fixed deadline: yielding extends nothing.
assert(drainedAfter<=300+1 and stats.admissionExpired==40-committed-stats.admissionCancelled-stats.admissionSuperseded,'every item that was not admitted expired at its own fixed 300-second deadline; yielding extended none: '..drainedAfter)
-- Per item, from the real event log: each expiry happened at that item's own
-- deadline, 300 seconds after its arrival, within one frame.
local expiredAt={}
for _,e in ipairs(Nexus.Sync.EventLog())do
 local name=e.text:match("^REJECT deferred summary '(fair%-a%-%d+)': catalog admission wait expired$")
 if name then assert(not expiredAt[name],'one expiry per item');expiredAt[name]=e.t end
end
local proven=0
for i=1,40 do
 local name='fair-a-'..i
 if not C.Get(name)then
  assert(H.puts[name].accepted==0,'an expired item was never submitted')
  local waited=assert(expiredAt[name],'expiry of '..name..' is recorded')-enqueuedAt
  assert(waited>=300 and waited<=300.06,name..' expired at its own fixed deadline: '..waited)
  proven=proven+1
 else assert(not expiredAt[name],'a committed item never expired')end
end
assert(proven==stats.admissionExpired,'every expiry is accounted for')
H.Advance(30,.05)
assert(Committed(C,'fair-a-')==committed,'no expired item is stored later')

-- 4. Pacing, alternation and no duplicate transmission. The bounded automatic
-- convergence passes and recovery requests are real later outbound traffic.
assert(#sends>=2,'fixture: several real transmissions happened under pressure')
local seen={}
for i,row in ipairs(sends)do
 assert(not seen[row.text],'no packet is transmitted twice: '..row.text:sub(1,40));seen[row.text]=true
 if i>1 then
  assert(row.t-sends[i-1].t>=1.1-1e-6,'ordinary send pacing is unchanged: '..(row.t-sends[i-1].t))
 end
end
local ids={}
for _,row in ipairs(sends)do
 local id=row.text:gsub('||','|'):match('^WLRQ|[^|]*|[^|]*|[^|]*|([^|]*)')
 if id then assert(not ids[id],'one transmission per request id');ids[id]=true end
end
assert(#H.actions==0,'zero gameplay mutation')
print('PASS fixed deadlines kept; '..#sends..' paced transmissions, none duplicated')
SendChatMessage=send

-- 5. Admission yields only to a transmission that can actually happen. With a
-- persistent wire blocker the queued request cannot be sent, so deferred work
-- keeps its ordinary progress; when the blocker clears, the request is sent
-- promptly and exactly once.
for _,blocker in ipairs({'combat','suspended'})do
 local function Block(H,on)
  if blocker=='combat' then H.combat=on else Nexus.SyncWire.suspended=on end
 end
 local progress={}
 for _,request in ipairs({false,true})do
  H,C=S.Boot(5);S.Hold(C)
  for i=1,8 do S.Receive('fair-c-'..i,'Peer',S.base+i,'Blocked dispatch '..i)end
  Block(H,true)
  if request then SlashCmdList.NEXUS('sync')end
  -- 120 simulated seconds: measured, both cases finish all eight items here
  -- in every run, while 60 seconds still catches unfinished control work.
  H.Advance(120,.05)
  local n=0;for i=1,8 do if C.Get('fair-c-'..i)then n=n+1 end end
  progress[request]=n
  assert(#H.sent==0 and #H.actions==0,'a blocked wire transmits nothing: '..blocker)
  if request then assert(Nexus.Sync.Stats().admissionYielded==0,'admission does not yield to a transmission that cannot happen: '..blocker)end
 end
 assert(progress[false]==8,'control: every deferred item is admitted under the blocker: '..blocker..' '..progress[false])
 assert(progress[true]==8,'a queued request that cannot be sent starves no inbound admission: '..blocker..' '..progress[true]..' of 8')
 -- Recovery under pressure.
 H,C=S.Boot(20);S.Hold(C)
 Pressure(40,'fair-d-')
 Block(H,true)
 -- A pending manual request accelerates catalog preparation, so the blocked
 -- window is kept short: most of the queue must still wait at recovery.
 H.Advance(7,.05);SlashCmdList.NEXUS('sync')
 H.Advance(4,.05)
 assert(Requests(H)==0 and Deferred()>=30,'fixture: request held by the blocker while most deferred items still wait')
 Block(H,false)
 local cleared,resolvedAtClear=H.now,Nexus.Sync.Stats().admissionResolved
 T.Until(H,function()return Requests(H)>0 or Deferred()==0 end,40000)
 local served=Nexus.Sync.Stats().admissionResolved-resolvedAtClear
 assert(Requests(H)==1 and served<=2 and Deferred()>=25,'after '..blocker..' clears the request is sent promptly, not behind the queue: '..served..' admitted first, after '..(H.now-cleared)..'s')
 H.Advance(5,.05)
 assert(Requests(H)==1 and #H.actions==0,'one transmission after recovery, no gameplay action')
 print('PASS '..blocker..': no yield while blocked ('..progress[true]..' vs control '..progress[false]..'); request sent '..string.format('%.1f',H.now-5-cleared)..'s after recovery with '..served..' admissions first')
end
