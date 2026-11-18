-- Issue #171 review repair (Spec P2 at 39d0c39): the transport factory's own
-- pre-submit observers (the previous packet's send_settled and this packet's
-- send_attempting) run other code. A Pause, or a quick Pause and Resume,
-- raised there stops the packet admitted before it from being submitted, with
-- no attempt counted; it ends dropped and is not sent after Resume. A packet
-- cancelled by such a callback is not sent and no other entry is popped. A
-- pause raised inside the native send itself leaves that submitted result as
-- it is. Real SessionPause and the public Transport.New factory; synthetic
-- native send only (the share_transport_prepared shape).
local failures={}
local function Case(name,fn)
 local ok,err=pcall(fn)
 print((ok and 'CASE PASS ' or 'CASE FAIL ')..name..(ok and '' or (': '..tostring(err))))
 if not ok then failures[#failures+1]=name end
end

local function Rig(hook)
 Nexus={};dofile('core/SessionPause.lua');dofile('core/SyncTransport.lua')
 local P=Nexus.SessionPause
 local r={now=0,sent={},events={},stats={}}
 r.q=Nexus.SyncInternals.Transport.New({maxBulk=8,maxControl=8,responseHeadroom=1,
  chatLimit=255,sendInterval=1.1,slowInterval=1.75,throttlePause=5,throttleSlowTime=20,
  controlBurstLimit=4,maxAttempts=3,cleanupBudget=2,now=function()return r.now end,
  escapedLen=function(s)return #s end,log=function()end,stats=r.stats,
  resolveChannel=function()return 1 end,channelLabel=function()return 1 end,
  sendChat=function(text)
   r.sent[#r.sent+1]=text
   if r.onSend then r.onSend(text) end
   return true
  end,
  canDispatch=function()return true end,addMessageFilter=function()end,
  -- As core/Sync.lua: the session pause admits no new packet.
  permit=function()return not P.IsPaused() end,
  observe=function(kind,fields,metadata)
   r.events[#r.events+1]={kind=kind,fields=fields,metadata=metadata}
   if hook then hook(r,kind,fields,metadata) end
  end})
 function r.Share(i)
  local status={kind='share',terminal=false}
  assert(r.q.EnqueueControl('share-'..i,{queueClass='share',operationKind='share',
   operationStatus=status,operationKey='share:'..i,shareId=tostring(i),expiresAt=r.now+120}))
 end
 function r.Advance(seconds) for _=1,math.floor(seconds/.05+.5) do r.now=r.now+.05;r.q.Pump(.05) end end
 function r.Count(kind,shareId)
  local n=0
  for _,e in ipairs(r.events) do
   if e.kind==kind and (shareId==nil or (e.metadata and e.metadata.shareId==shareId)) then n=n+1 end
  end
  return n
 end
 function r.Sent(text) local n=0;for _,t in ipairs(r.sent) do if t==text then n=n+1 end end;return n end
 r.P=P
 return r
end
local function Transition(P,mode)
 if mode=='control' then return end
 P.Pause();if mode=='quick' then P.Resume() end
end

-- T1. The reproduced observer: this packet's own send_attempting.
for _,mode in ipairs({'control','held','quick'}) do
 Case('T1 send_attempting '..mode,function()
  local hit=0
  local r=Rig(function(r,kind)
   if kind=='send_attempting' and hit==0 then hit=1;Transition(r.P,mode) end
  end)
  r.Share(1);r.Advance(3)
  assert(hit==1,'the observer ran')
  if mode=='control' then
   assert(#r.sent==1 and r.stats.sendAttempts==1 and r.stats.sent==1,'control: sent once and counted')
   return
  end
  assert(#r.sent==0,'no native send after the transition: sends='..#r.sent)
  assert((r.stats.sendAttempts or 0)==0 and (r.stats.attempted or 0)==0 and (r.stats.sent or 0)==0,
   'no attempt is counted for an unsent packet')
  assert(r.Count('send_dropped','1')==1 and r.Count('send_attempted','1')==0,'it ends dropped, never attempted')
  assert(r.q.Snapshot().outbound==0,'the stale packet left the queue')
  if mode=='held' then r.P.Resume() end
  r.Advance(5)
  assert(#r.sent==0,'it is not sent after Resume')
 end)
end

-- T2. The preceding packet's send_settled observer. Share 1 was really sent;
-- the transition happens while Share 2 is about to go out.
for _,mode in ipairs({'control','held','quick'}) do
 Case('T2 send_settled '..mode,function()
  local hit=0
  local r=Rig(function(r,kind,_,metadata)
   if kind=='send_settled' and metadata and metadata.shareId=='1' and hit==0 then hit=1;Transition(r.P,mode) end
  end)
  r.Share(1);r.Advance(1.2)
  assert(r.Sent('share-1')==1 and r.stats.sendAttempts==1,'setup: Share 1 was sent')
  r.Share(2);r.Advance(3)
  assert(hit==1,'the settled observer ran')
  assert(r.Count('send_settled','1')==1 and r.Count('send_dropped','1')==0,'Share 1 stays truthfully settled, once')
  if mode=='control' then
   assert(r.Sent('share-2')==1 and r.stats.sendAttempts==2,'control: Share 2 is sent')
   return
  end
  assert(r.Sent('share-2')==0 and r.stats.sendAttempts==1,'Share 2 is not sent and not counted')
  assert(r.Count('send_dropped','2')==1,'Share 2 ends dropped')
  if mode=='held' then r.P.Resume() end
  r.Advance(5)
  assert(r.Sent('share-2')==0 and r.Count('send_settled','1')==1,'nothing is sent or settled again after Resume')
 end)
end

-- T3. A pause inside the native send itself: that submission was entered, so
-- its result stands. Nothing is retracted, dropped or sent twice.
for _,mode in ipairs({'held','quick'}) do
 Case('T3 inside the native send '..mode,function()
  local r=Rig()
  r.onSend=function() r.onSend=nil;Transition(r.P,mode) end
  r.Share(1);r.Advance(1.2)
  assert(#r.sent==1 and r.stats.sendAttempts==1 and r.stats.sent==1,'the entered send counts once')
  assert(r.Count('send_attempted','1')==1 and r.Count('send_dropped','1')==0,'reported as attempted, not dropped')
  if mode=='held' then r.P.Resume() end
  r.Advance(5)
  assert(#r.sent==1 and r.q.Snapshot().outbound==0,'not sent again')
 end)
end

-- T4. A callback that cancels the selected packet itself: it is not sent and
-- the packet behind it is not popped in its place; that one is sent next, once.
Case('T4 cancelled inside send_attempting',function()
 local hit=0
 local r=Rig(function(r,kind,_,metadata)
  if kind=='send_attempting' and metadata and metadata.requestId=='r1' and hit==0 then
   hit=1;r.q.CancelRequest('r1','peer')
  end
 end)
 for i=1,2 do
  assert(r.q.EnqueueControl('request-'..i,{queueClass='request',requestId='r'..i,requester='peer',
   operationKind='share',operationStatus={kind='share',terminal=false},operationKey='req:'..i,
   shareId='r'..i,expiresAt=120}))
 end
 r.Advance(1.2)
 assert(hit==1,'the observer ran for the selected packet r1')
 assert(r.Sent('request-1')==0 and r.Sent('request-2')==0,'nothing is sent in that turn')
 r.Advance(3)
 assert(r.Sent('request-1')==0 and r.Sent('request-2')==1,'the next packet is sent once, in its own turn')
 assert(r.q.Snapshot().outbound==0,'queue drained exactly')
end)

assert(#failures==0,'failed cases: '..table.concat(failures,', '))
print('PASS session pause holds the transport after its pre-submit observers')
