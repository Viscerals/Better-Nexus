-- Focused queue boundary: use the real transport factory and synthetic wire.
Nexus={};dofile('core/SyncTransport.lua')
local now,sent,events,stats=0,{},{},{}
local allowed,channel=true,1
local q=Nexus.SyncInternals.Transport.New({maxBulk=8,maxControl=8,responseHeadroom=1,
 chatLimit=255,sendInterval=1.1,slowInterval=1.75,throttlePause=5,throttleSlowTime=20,
 controlBurstLimit=4,maxAttempts=3,cleanupBudget=2,now=function()return now end,
 escapedLen=function(s)return #s end,log=function()end,stats=stats,
 resolveChannel=function()return channel end,channelLabel=function()return channel end,
 sendChat=function(text)sent[#sent+1]={text=text,at=now};return true end,
 canDispatch=function()return allowed end,addMessageFilter=function()end,
 observe=function(kind,fields,metadata)events[#events+1]={kind=kind,fields=fields,metadata=metadata}end})
local function Share(i,ttl)
 local status={kind='share',terminal=false}
 assert(q.EnqueueControl('share-'..i,{queueClass='share',operationKind='share',
  operationStatus=status,operationKey='share:'..i,shareId=tostring(i),expiresAt=now+(ttl or 120)}))
end
local function Advance(seconds,prepared)
 for _=1,math.floor(seconds/.05+.5)do now=now+.05;if prepared then q.PumpPreparedShare(.05)else q.Pump(.05)end end
end
assert(q.Enqueue('bulk',{expiresAt=999}))
assert(q.EnqueueControl('request',{queueClass='request',expiresAt=999}))
assert(q.EnqueueControl('claim',{queueClass='claim',expiresAt=999}))
for i=1,5 do Share(i)end
Advance(7,true)
assert(#sent==5,'all five approved Shares progress even when the withheld bulk fairness turn is due')
for i=1,5 do
 assert(sent[i].text=='share-'..i,'Share FIFO preserved')
 if i>1 then assert(sent[i].at-sent[i-1].at>=1.099,'same paced transport interval')end
end
Advance(3,true)
assert(#sent==5 and q.Snapshot().outbound==3,'restricted pump cannot send request, claim or bulk')
Advance(1.2,false)
assert(sent[6].text=='bulk','normal pump honors retained bulk fairness after readiness')
Advance(3,false)
assert(sent[7].text=='request' and sent[8].text=='claim','normal control priority resumes')
assert(q.Snapshot().outbound==0,'original queue accounting drains exactly')
-- A share class label without its real operation owner is insufficient.
assert(q.EnqueueControl('unowned',{queueClass='share',expiresAt=now+2}))
Advance(3,true);assert(#sent==8 and q.Snapshot().outbound==0,'unowned share label cannot bypass the gate')
Share(6);allowed=false;Advance(2,true);assert(#sent==8,'wire guard remains authoritative')
allowed=true;channel=nil;Advance(2,true);assert(#sent==8,'channel remains required')
channel=1;Advance(1.2,true);assert(#sent==9 and sent[9].text=='share-6','one original Share resumes after guards')
assert(q.NoteTransportNotice('waiting to send'),'existing throttle attribution accepts the real recent attempt')
local attempted=#sent;Advance(4.9,true);assert(#sent==attempted,'existing throttle pause still applies')
Advance(3,true);assert(#sent==attempted+1 and sent[#sent].text=='share-6','existing bounded transport retry retains the same packet')
Advance(5,true);assert(#sent==attempted+1,'settled transport does not create a duplicate Share')
allowed=false;Share(7,2);Advance(3,true)
local expired=0
for _,e in ipairs(events)do
 if e.kind=='operation_terminal' and e.metadata.shareId=='7' then
  assert(e.fields.outcome=='expired');expired=expired+1
 end
end
assert(expired==1 and q.Snapshot().outbound==0,'passive expiry settles the owning operation once')
-- A recently attempted non-Share can be requeued ahead of an admitted Share.
-- Its throttle attribution must not cause head-of-line starvation afterwards.
allowed=true;assert(q.EnqueueControl('earlier-request',{queueClass='request',requestId='r2',requester='peer',expiresAt=now+120}))
Advance(2,false);assert(sent[#sent].text=='earlier-request')
Share(8);Share(9)
assert(q.NoteTransportNotice('waiting to send'))
local before=#sent;Advance(4.9,true);assert(#sent==before,'throttle pause also applies with non-Share head')
Advance(5,true)
assert(#sent==before+2 and sent[before+1].text=='share-8' and sent[before+2].text=='share-9','admitted Shares progress in FIFO order past a withheld requeued request')
assert(q.Snapshot().outbound==1 and q.Snapshot().requestRelated==1,'earlier non-Share is retained, not dropped or dispatched')
Advance(2,false);assert(sent[#sent].text=='earlier-request' and q.Snapshot().outbound==0,'normal readiness later dispatches the original non-Share')
print('PASS restricted Share selection, FIFO, shared pacing, fairness, wire/channel guards, existing throttle retry and exact expiry')
