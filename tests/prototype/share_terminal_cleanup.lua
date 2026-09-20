-- Independent composition of requeued non-Share head plus blocked/stale Share.
Nexus={};dofile('core/SyncTransport.lua')
local function Scenario(invalidate)
 local now,sent,terminal,allowed,current=0,{}, {},true,true
 local q=Nexus.SyncInternals.Transport.New({maxBulk=8,maxControl=8,responseHeadroom=1,
  chatLimit=255,sendInterval=1.1,throttlePause=5,throttleSlowTime=20,
  maxAttempts=3,cleanupBudget=2,now=function()return now end,
  escapedLen=function(s)return #s end,log=function()end,stats={},
  resolveChannel=function()return 1 end,channelLabel=function()return 1 end,
  sendChat=function(text)sent[#sent+1]=text;return true end,
  canDispatch=function()return allowed end,operationCurrent=function()return current end,
  addMessageFilter=function()end,
  observe=function(kind,fields,metadata)
   if kind=='operation_terminal' then terminal[#terminal+1]={fields=fields,metadata=metadata}end
  end})
 local function Advance(seconds,restricted)
  for _=1,math.floor(seconds/.05+.5)do now=now+.05;if restricted then q.PumpPreparedShare(.05)else q.Pump(.05)end end
 end
 assert(q.EnqueueControl('earlier-request',{queueClass='request',requestId='review-request',requester='review-peer',expiresAt=300}))
 Advance(1.2,false);assert(#sent==1)
 local approval={kind='share',terminal=false}
 assert(q.EnqueueControl('approved-share',{queueClass='share',operationKind='share',operationStatus=approval,operationKey='review-share',shareId='review-share',expiresAt=now+120}))
 assert(q.NoteTransportNotice('waiting to send'))
 allowed=false
 if invalidate then current=false end
 Advance(121,true)
 print('OBSERVED',invalidate and 'scope-invalid' or 'expired','seconds',now,'terminal-events',#terminal,'outbound',q.Snapshot().outbound,'requestRelated',q.Snapshot().requestRelated,'wire-sends',#sent)
 assert(#sent==1 and q.Snapshot().requestRelated==1,'withheld original request must remain queued without a second send')
 local timely=#terminal==1 and q.Snapshot().outbound==1
 Advance(180,true)
 print('EVENTUAL',invalidate and 'scope-invalid' or 'expired','seconds',now,'terminal-events',#terminal,'outbound',q.Snapshot().outbound,'wire-sends',#sent)
 assert(#terminal==1,'eventual settlement must occur exactly once')
 assert(terminal[1].fields.outcome==(invalidate and 'superseded' or 'expired'))
 assert(timely,'prepared Share must publish its terminal result despite an unrelated unexpired control head')
end
local expired,expiredWhy=pcall(Scenario,false)
local invalid,invalidWhy=pcall(Scenario,true)
print('CASE_RESULTS',expired,expiredWhy,invalid,invalidWhy)
assert(expired and invalid,'both terminal outcomes must be independent of withheld unrelated packet lifetime')
print('PASS terminal Share expiry and approval invalidation behind a withheld requeued request')

-- Exercise bounded passive rotation past live Shares, with no pump at all.
local function BoundedSweep(invalidate)
 local now,sent,checks,events=0,0,0,{}
 local stats,owners={},{}
 local q=Nexus.SyncInternals.Transport.New({maxBulk=8,maxControl=128,responseHeadroom=1,
  chatLimit=255,sendInterval=1.1,throttlePause=5,throttleSlowTime=20,
  maxAttempts=3,cleanupBudget=2,now=function()return now end,
  escapedLen=function(s)return #s end,log=function()end,stats=stats,
  resolveChannel=function()return 1 end,channelLabel=function()return 1 end,
  sendChat=function()sent=sent+1;return true end,
  operationCurrent=function(status)checks=checks+1;return not (invalidate and status.stale)end,
  addMessageFilter=function()end,
  observe=function(kind,fields,metadata)
   if kind=='operation_terminal' then
    assert(not events[metadata.shareId],'each owned Share settles exactly once')
    events[metadata.shareId]=fields.outcome
   end
  end})
 assert(q.EnqueueControl('request',{queueClass='request',requestId='budget-request',requester='peer',expiresAt=1000}))
 now=1.2;q.Pump(1.2);assert(sent==1)
 assert(q.Enqueue('bulk',{expiresAt=1000}))
 for i=1,99 do
  local status={kind='share',terminal=false,stale=i%2==0};owners[i]=status
  assert(q.EnqueueControl('share-'..i,{queueClass='share',operationKind='share',
   operationStatus=status,operationKey='bounded-'..i,shareId=tostring(i),
   expiresAt=(not invalidate and status.stale) and 121.2 or 1000}))
 end
 assert(q.NoteTransportNotice('waiting to send'))
 now=122.2
 for _=1,100 do
  checks=0;local before=stats.cleanupInspected or 0
  q.Housekeep()
  assert(checks<=2,'prepared cleanup must respect its per-turn inspection budget')
  assert((stats.cleanupInspected or 0)-before<=4,'head and prepared cleanup remain bounded')
  assert(sent==1,'passive cleanup cannot invoke another wire submission')
 end
 for i=1,99 do
  assert(events[tostring(i)]==(i%2==0 and (invalidate and 'superseded' or 'expired') or nil),
   'rotation must reach every stale Share and retain every live Share')
 end
 assert(q.Snapshot().outbound==52 and q.Snapshot().requestRelated==1,
  'cleanup retains 50 live Shares, the withheld request and bulk packet')
 -- The cursor must also settle the remaining owners and reset cleanly.
 invalidate=true
 for _,owner in ipairs(owners)do owner.stale=true end
 for _=1,100 do checks=0;q.Housekeep();assert(checks<=2 and sent==1)end
 assert(q.Snapshot().outbound==2 and q.Snapshot().requestRelated==1)
 for i=1,99 do assert(events[tostring(i)])end
 q.Reset();assert(q.Snapshot().outbound==0)
 local status={kind='share',terminal=false,stale=true}
 assert(q.EnqueueControl('reset-share',{queueClass='share',operationKind='share',
  operationStatus=status,operationKey='reset-share',shareId='reset-share',expiresAt=1000}))
 q.Housekeep();assert(events['reset-share']=='superseded' and q.Snapshot().outbound==0 and sent==1)
end
BoundedSweep(false);BoundedSweep(true)
print('PASS bounded passive rotation, live packet retention, exact queue accounting and reset')
