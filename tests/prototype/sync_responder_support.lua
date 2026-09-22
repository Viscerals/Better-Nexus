-- Shared fixture for the responder-turn tests. An owner shares an exact
-- multi-chunk record while the requester is not listening, so only ordinary
-- reconciliation can deliver it: requester Sync Now -> WLRQ through the real
-- channel callback -> responder election (WLRC) and bucket claim (WLBC), both
-- carrying the request ID -> full-record chunks (WLRB) -> exact commit. Real lifecycle, reconciler, transport,
-- admission, catalog and projection on two isolated runtimes. Nothing calls
-- Sync.OnUpdate or a preparation function directly. Synthetic data only.
local P=dofile('tests/prototype/sync_pair_support.lua')
local S={P=P}
local function Text(packet)return (packet.text:gsub('||','|'):gsub('^P%d+:',''))end
function S.Summary(p,tag,i)
 local owner='TurnTraffic'..((i-1)%8+1)
 local d={id='turn-'..tag..'-'..i,t='Synthetic interleaved traffic '..i,a=owner..'-Ebonhold',
  o=p.e.Nexus.Identity.OwnerKey(owner,'Ebonhold'),c='MAGE',m=p.e.time()+i,h='a1',n=3}
 P.Channel(p,'WLBI|'..d.a..'|'..p.e.Nexus.Codec.Base64Encode(p.e.Nexus.Codec.JSONEncode(d)),d.a)
 return d.id
end
-- options: label, rows, names, traffic={'A','B'} (one valid summary at every
-- ready frame of that peer), idle=seconds the responder stays ready and idle
-- before the request, afterRequest=function(run) called on the responder
-- between the delivered WLRQ and its next frame, inflight=true (a catalog
-- transaction is in flight on the responder when the request arrives),
-- stop=function(run) replaces the default wait for the exact full record.
function S.Scenario(o)
 local A,B=P.Boot(o.names,o.rows)
 local run={A=A,B=B,label=o.label,arrivals={A=0,B=0},chunks={},seen={}}
 local function Stats(p)return p.e.Nexus.Sync.Stats()end
 run.Stats=Stats
 local echoes={};for j=1,79 do echoes[j]={spellId=200000+j,quality=j%4,stacks=1}end
 A.H.perks.serverBuildSlots[102].echoes=echoes
 run.id=P.Post(A,'NEXUS-TEST-RESPONDER-'..o.label)
 A.T.Until(A.H,function()
  local status=A.e.Nexus.CommunityBuilds.ShareStatus(run.id)
  return status and status.localSaved and P.Ready(A)
 end)
 -- The owner's own Share packets are sent by the real transport and are
 -- never delivered: the requester is not listening yet.
 A.H.Advance(45,.05);A.cursor=#A.H.sent
 run.source=assert(A.e.Nexus.BuildCatalog.Get(run.id));assert(#run.source.echoes==79,'fixture: exact 79-entry record saved by the real Share owner')
 assert(B.e.Nexus.BuildCatalog.Get(run.id)==nil,'fixture: the requester has never seen the record')
 -- Admission counter read inside the responder's real send calls (observe only).
 local atSend={}
 for _,name in ipairs({'SendChatMessage','SendAddonMessage'})do
  local real=A.e[name]
  A.e[name]=function(...)atSend[#A.H.sent+1]=Stats(A).admissionResolved or 0;return real(...)end
 end
 local pendingInject=false
 run.base=A.e.Nexus.Sync.ResponseStats()
 P.before=function(p,q,code)
  if p==B and code=='WLRQ' then run.requests=(run.requests or 0)+1 end
  if p==A and code=='WLRC' and not run.firstClaimId then
   run.firstClaimId,run.firstClaimAt=Text(p.H.sent[p.cursor]):match('(c1%-[%w%-]+)'),A.H.now
  end
  if p==A and (code=='WLRC' or code=='WLBC') and run.requestId and Text(p.H.sent[p.cursor]):find('|'..run.requestId..'|',1,true) then
   run.claims=(run.claims or 0)+1;run.claimAt=run.claimAt or A.H.now;run.bucketClaim=run.bucketClaim or code=='WLBC'
  end
  if p==B and code=='WLRQ' and not run.requestAt then
   local _,requester,_,_,requestId=Text(p.H.sent[p.cursor]):match('^(WLRQ)|([^|]*)|([^|]*)|?([^|]*)|?([^|]*)')
   run.requestAt,run.requestText,run.requester=A.H.now,Text(p.H.sent[p.cursor]),requester
   run.requestId=Text(p.H.sent[p.cursor]):match('(c1%-[%w%-]+)')
   -- In flight: one valid summary takes the ready catalog just before the
   -- request is delivered in the same frame.
   if o.inflight then
    -- A catalog transaction of the responder's own, started in this frame.
    -- A received summary is not used here: when the responder already owes a
    -- response it is retained instead of taking the catalog, which is the
    -- correct receiver behaviour but not the case under test.
    local C=A.e.Nexus.BuildCatalog
    local row
    for _,id in ipairs({run.id,'synthetic-startup-1','synthetic-startup-2'})do
     if not row and id and C.Get(id) then row=A.H.Clone((C.Get(id))) end
    end
    assert(row,'fixture: a stored record to copy')
    -- A separate synthetic id: no record the test verifies is touched.
    row.id='inflight-holder-'..tostring(o.label)
    row.title='In-flight transaction'
    row.isMine=false;row.ownerVerified=true
    row.postedAt=tonumber(row.postedAt) or 1
    row.lastModified=(tonumber(row.lastModified) or 1)+1
    -- A staged write: it takes the catalog transaction without publishing a
    -- represented-data revision, so it adds no Share, no serialization and no
    -- outbound traffic of its own.
    local ok,why,ticket=C.PutDeferred(row)
    assert(ok==nil and why=='ROOT_MUTATION_PENDING' and type(ticket)=='table',
     'fixture: the responder catalog really took a transaction: '..tostring(why))
    run.holder,run.holderTicket=row.id,ticket
    run.trafficOn=true
   end
   pendingInject=o.afterRequest~=nil
  elseif p==A and code=='WLRB' then
   local id,index,total=Text(p.H.sent[p.cursor]):match('^WLRB|[^|]+|([^|]+)|[^|]+|(%d+)/(%d+)|')
   if id==run.id then
    run.chunks[#run.chunks+1]={time=p.H.now,index=tonumber(index),total=tonumber(total),
     resolved=assert(atSend[p.cursor],'every transmitted chunk was observed at its send call'),
     requests=run.requests or 0,serializations=A.e.Nexus.Sync.ResponseStats().buildSerializations-run.base.buildSerializations}
   end
  end
 end
 -- Per-frame observation and traffic on the real frame clock.
 for name,p in pairs({A=A,B=B})do
  local advance=p.H.Advance
  local traffic=false;for _,n in ipairs(o.traffic or {})do traffic=traffic or n==name end
  p.H.Advance=function(...)
   if p==A and pendingInject then pendingInject=false;o.afterRequest(run)end
   local r=advance(...)
   if p==A and run.requestAt then
    -- An accepted write reports a busy catalog from its first frame on.
    if run.readyAtRequest==nil then run.readyAtRequest=P.Ready(A) end
    local work,response=A.e.Nexus.Sync.WorkState(),A.e.Nexus.Sync.ResponseStats()
    if work.pendingResponses>0 then run.seen.pending=run.seen.pending or A.H.now end
    if run.seen.pending and work.pendingResponses==0 then run.seen.pendingEnd=run.seen.pendingEnd or A.H.now end
    if response.entryPreparations>run.base.entryPreparations then run.seen.preparation=run.seen.preparation or A.H.now end
    if response.buildSerializations>run.base.buildSerializations then run.seen.serialization=run.seen.serialization or A.H.now end
   end
   if traffic and run.trafficOn and P.Ready(p) then
    run.arrivals[name]=run.arrivals[name]+1;S.Summary(p,o.label..'-'..name,run.arrivals[name])
   end
   return r
  end
 end
 -- Idle readiness on the responder alone, so that the requester's first
 -- request is the manual one below.
 if o.idle then A.H.Advance(o.idle,.05);A.cursor=#A.H.sent;assert(P.Ready(A),'fixture: responder idle and ready') end
 -- With an in-flight fixture the traffic starts at the request, so the
 -- holder finds an idle catalog and really takes it.
 run.trafficOn=not o.inflight
 B.e.SlashCmdList.NEXUS('sync');run.clicked=B.H.now
 run.done=pcall(P.Until,function()if o.stop then return o.stop(run)end;return P.Full(B,run.id)~=nil end,o.limit or 4000)
 run.seconds=B.H.now-run.clicked
 run.response=A.e.Nexus.Sync.ResponseStats()
 local function At(t)return t and string.format('%.1f',t-run.requestAt) or 'never' end
 print(string.format('OBSERVED %s complete=%s after=%.1fs request=%s ready_at_request=%s pending=+%s preparation=+%s serialization=+%s pending_end=+%s chunks=%d responder_held=%s requester_held=%s useful=%s new=%s',
  o.label,tostring(run.done),run.seconds,tostring(run.requestId),tostring(run.readyAtRequest),At(run.seen.pending),At(run.seen.preparation),
  At(run.seen.serialization),At(run.seen.pendingEnd),#run.chunks,tostring(Stats(A).admissionHeld),tostring(Stats(B).admissionHeld),
  tostring(Stats(B).useful),tostring(Stats(B).requestNew)))
 assert(run.requestId and run.requester==B.name:match('^[^-]+'),'fixture: one ordinary WLRQ with its request ID reached the responder through the channel callback')
 return run
end
-- Responder preparation within the unchanged response lifetime, bound to the
-- original request: its ID is on the responder's election and bucket claims,
-- the election claim precedes the first chunk,
-- it is the only request the requester has sent when the first chunk of the
-- target record leaves, and that record is the one serialization so far.
function S.Served(run)
 assert(run.claimAt and run.bucketClaim,'the responder sent its election claim and its bucket claim under the original request ID: '..tostring(run.requestId))
 local first=assert(run.chunks[1],'a full-record chunk of the target record was transmitted')
 assert(first.index==1 and first.requests==1 and first.serializations==1 and first.time>=run.claimAt,string.format('the first target chunk follows the claim of the original and only request, after exactly one serialization: index=%d requests=%d serializations=%d chunk=%.2f claim=%.2f',first.index,first.requests,first.serializations,first.time,run.claimAt))
 assert(run.seen.pending and run.seen.pending-run.requestAt<=.11,'the delivered request became a pending response at once')
 assert(run.seen.preparation and run.seen.serialization,'the responder prepared the response and serialized the record')
 assert(run.seen.serialization-run.requestAt<30,'first serialization is inside the unchanged 30-second response lifetime')
end
-- Exact remote commit. A sent request, a summary, a completed chunk run and an
-- admission ticket are all distinct from this.
function S.Exact(run,why)
 local row=P.Full(run.B,run.id)
 assert(run.done and row,why)
 assert(row.ownerKey==run.source.ownerKey and row.lastModified==run.source.lastModified and row.title==run.source.title and row.isMine~=true,'owner, revision and title match the source')
 assert(#row.echoes==79 and run.B.T.Equal(row.echoes,run.source.echoes),'the requester committed the exact record: every ID, quality and copy')
 local stats=run.Stats(run.B)
 assert(stats.requestId==run.requestId and run.requests==1,'the result belongs to the original request; no later request was sent: '..tostring(stats.requestId)..' after '..tostring(run.requests))
 assert(stats.useful==true and (stats.requestNew or 0)>=1,'the request itself reports a useful result; a sent request alone is not the transaction')
 assert(#run.A.H.actions==0 and #run.B.H.actions==0,'zero gameplay mutation')
end
-- Every attempt is one contiguous chunk run at ordinary pacing with no
-- deferred admission between its chunks. Returns complete attempts, attempts.
function S.Attempts(run)
 local attempts,current,complete={},nil,0
 for _,c in ipairs(run.chunks)do
  if c.index==1 then current={total=c.total};attempts[#attempts+1]=current
  else assert(current and c.total==current.total and c.index==#current+1,'chunks of one attempt are contiguous: '..c.index..'/'..c.total)end
  current[#current+1]=c
 end
 for _,attempt in ipairs(attempts)do
  assert(attempt.total>1,'the transfer really uses several chunks')
  for i=2,#attempt do
   assert(attempt[i].resolved==attempt[i-1].resolved,'a started transfer is not interleaved with admissions: chunk '..attempt[i].index..'/'..attempt.total)
   assert(attempt[i].time-attempt[i-1].time>=1.1-1e-6,'ordinary send pacing is unchanged')
  end
  if #attempt==attempt.total then complete=complete+1 end
 end
 return complete,#attempts
end
return S
