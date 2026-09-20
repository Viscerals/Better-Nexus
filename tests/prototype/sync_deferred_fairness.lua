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
-- Fair progress: the request may wait for the catalog transaction that is
-- already in flight and for the turns in which it is prepared and paced. It
-- must not wait behind the queue. On 8ab9fc2 this count was 8 to 40.
assert(servedFirst<=3 and deferredAtSend>=30,'an explicit Sync Now request is not starved behind deferred inbound admissions: '..servedFirst..' were admitted first, '..tostring(deferredAtSend)..' still waited')
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
for i=1,40 do if not C.Get('fair-a-'..i)then assert(H.puts['fair-a-'..i].accepted==0,'an expired item was never submitted')end end
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

-- 5. When transport cannot send, the catalog is not left idle.
H,C=S.Boot(20);S.Hold(C)
Pressure(8,'fair-b-')
H.Advance(7,.05);SlashCmdList.NEXUS('sync')
local connected=Nexus.Sync.IsConnected
Nexus.Sync.IsConnected=function()return false end
local yieldedBefore=Nexus.Sync.Stats().admissionYielded
T.Until(H,function()return Nexus.Sync.Stats().admissionResolved>=2 end,40000)
assert(Nexus.Sync.Stats().admissionYielded==yieldedBefore,'a transport that cannot send does not hold deferred admission')
Nexus.Sync.IsConnected=connected
print('PASS deferred admission proceeds while transport cannot send')
