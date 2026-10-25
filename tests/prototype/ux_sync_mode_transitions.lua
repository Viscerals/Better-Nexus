-- UX M5 14d (LP-12): what happens to Sync work when the player applies a
-- Sync mode choice, through the real SyncModePolicy.ApplyChoice -> Store owner
-- route, in two real runtimes (sync_pair_support; only packets captured from
-- real SendChatMessage/SendAddonMessage calls cross the bridge).
-- Healthy behaviour (EXPECT, fails on the preimage d15ba07c and accepted M4,
-- which have no ApplyChoice): Apply itself sends and queues nothing; after
-- Automatic -> Off, the remaining chunk of an answer already queued is
-- dropped at the existing final-submit check with the mode reason and nothing
-- more is sent (no resurrection when time passes or a peer asks); switching
-- back to Automatic sends nothing by itself, and no later packet continues
-- the dropped transfer or answers its old request, judged by packet identity
-- (build, version, chunk index, requester, request ID), not by silence;
-- later ordinary work resumes under its own new request identity;
-- a Manual Sync Now grant keeps its identity through a same-choice no-op,
-- a queued Manual request is ended by the existing cancellation when Off is
-- applied (terminal reason sync_mode), and applying Manual again does not
-- revive it.
-- Unchanged (GUARD): a mode refusal never suspends the wire; inbound shared
-- records are still received and stored under Off; no game action.
-- M5 14E-Q1 (continuation 40): exact identity and per-entry ownership.
-- Packet identity is linked to the dropped transfer only through its request
-- ID together with its requester. A same-ID chunk from another requester and
-- the old ID without a requester are kept apart; unattributable traffic stays
-- not-linkable. Each queue entry is also observed through the production
-- owners, by pass-through recorders that return the real results: its
-- admission (Transport.EnqueueBatch/EnqueueControl, with its metadata and
-- expiresAt) and its transport events (send_attempted, send_dropped, as Sync
-- hands them to Session.HandleTransportEvent). The exact request scope is read
-- with Transport.RequestSnapshot.
-- EXPECT:
--  T1  the crossing chunk is the entry admitted for that requester, request
--      and build, sent before its own unchanged deadline; each remaining
--      chunk ends once, dropped for the saved mode before that deadline; the
--      queue then owns nothing of the request; nothing of it is admitted or
--      attempted again; the later request's work is admitted after the switch
--      back under its own identity and a later deadline, and sent before that
--      deadline (fresh work on a live request, not a revived entry).
--  T2  the queued manual request is one entry of its own request, carrying
--      the active grant and its deadline; it leaves the queue unattempted
--      before that deadline, ended by the session's mode cancellation; Manual
--      again admits nothing under it.
-- Elapsed time and aggregate counters are not used as proof. The accepted M4
-- lifetime and retry controls are not repeated here.
-- Continuation 41: "before" and "after" an Apply are call order, not time.
-- Recorder entries carry one ordinal (n) shared by admissions and events, and
-- each boundary is the ordinal captured just before the Apply. The paired
-- harness sends, delivers and applies inside one tick (sync_pair_support
-- Step), so a timestamp cannot separate an earlier same-tick record from a
-- later one. Timestamps remain for deadlines only. SETUP controls in T1 and T2
-- show that the same-tick record from before the Apply is excluded, and that a
-- same-tick probe recorded after it is included. The probe is an empty packet,
-- which the transport refuses before any stats, queue or event.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
local Pair=dofile('tests/prototype/sync_pair_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('ux_sync_mode_transitions')

local function Apply(peer,mode)
 local policy=peer.e.Nexus.SyncModePolicy
 if type(policy.ApplyChoice)~='function' then return false,'no-policy-route' end
 return policy.ApplyChoice(mode)
end
local function Stats(peer) return peer.e.Nexus.Sync.Stats() or {} end

-- The peer's own Sync session and transport queue: the instances Sync made at
-- load, which its update steps (the module field Sync._defaultSteps) close
-- over. Read only, as catalog_idle_frames reads the lifecycle.
local function Upvalue(fn,name)
 if type(fn)~='function' then return nil end
 for i=1,255 do
  local n,v=debug.getupvalue(fn,i)
  if not n then break end
  if n==name then return v end
 end
end
local function Owners(peer)
 local steps=peer.e.Nexus.Sync._defaultSteps
 local session,transport
 for _,step in ipairs(type(steps)=='table' and steps or {}) do
  if step.name=='auto.sync' then session=Upvalue(step.run,'Session') end
  if step.name=='transport.pump' then transport=Upvalue(step.run,'Transport') end
 end
 return session,transport
end
local META={'requester','requestId','transferId','buildId','queueClass','enqueuedAt','expiresAt',
 'chunkOrdinal','chunkTotal','attempts','manualGrant'}
local function Scalars(t)
 local out={}
 if type(t)=='table' then
  for _,k in ipairs(META) do
   local v=t[k];local kind=type(v)
   if kind=='string' or kind=='number' or kind=='boolean' then out[k]=v end
  end
 end
 return out
end
local function Pack(...) return {n=select('#',...),...} end
-- Pass-through recorders. Each production call still runs, with its own
-- arguments, and its results are returned unchanged. Every entry takes the
-- next call-order ordinal (rec.seq): an admission when its call begins, an
-- event when it is reported (so an event raised inside an admission comes after it).
local function Record(peer)
 local session,transport=Owners(peer)
 local rec={admissions={},events={},session=session,transport=transport,seq=0}
 local function Next() rec.seq=rec.seq+1;return rec.seq end
 if type(transport)=='table' then
  for _,name in ipairs({'EnqueueBatch','EnqueueControl'}) do
   local real=transport[name]
   if type(real)=='function' then
    transport[name]=function(payload,metadata,...)
     local n,at=Next(),peer.H.now
     local r=Pack(real(payload,metadata,...))
     rec.admissions[#rec.admissions+1]={n=n,at=at,route=name,queued=r[1],why=r[2],
      chunks=type(payload)=='table' and #payload or 1,m=Scalars(metadata)}
     return unpack(r,1,r.n)
    end
   end
  end
 end
 if type(session)=='table' and type(session.HandleTransportEvent)=='function' then
  local real=session.HandleTransportEvent
  session.HandleTransportEvent=function(kind,fields,metadata,...)
   rec.events[#rec.events+1]={n=Next(),at=peer.H.now,kind=kind,
    reason=type(fields)=='table' and fields.reason or nil,
    outcome=type(fields)=='table' and fields.outcome or nil,m=Scalars(metadata)}
   return real(kind,fields,metadata,...)
  end
 end
 return rec
end
local function Of(m,requester,requestId) return m.requester==requester and m.requestId==requestId end
-- The recorder-boundary probe: an empty packet through the recorded
-- production transport, with an identity no real work uses. SyncTransport
-- refuses it ("invalid packet") before any stats, queue entry or event
-- (ValidatePayload at the top of EnqueueControl), so it changes nothing; it
-- only shows whether a call made after a boundary, in the same tick, is recorded
-- after that boundary.
local PROBE={requester='BoundaryControl-Ebonhold',requestId='c1-boundary-control'}
local function Probe(rec)
 if type(rec.transport)~='table' or type(rec.transport.EnqueueControl)~='function' then return nil end
 rec.transport.EnqueueControl('',{requester=PROBE.requester,requestId=PROBE.requestId,transferId=PROBE.requestId,queueClass='request'})
 for i=#rec.admissions,1,-1 do
  local a=rec.admissions[i]
  if Of(a.m,PROBE.requester,PROBE.requestId) then return a end
 end
end

-- Field-level packet identity: the wire code and its '|' fields after the chat
-- escape and the addon protocol tag are removed (core/Sync.lua formats).
local function Fields(text)
 local plain=tostring(text or ''):gsub('||','|'):gsub('^P%d+:','')
 local f={}
 for field in (plain..'|'):gmatch('([^|]*)|') do f[#f+1]=field end
 return f
end
local function Copy(f) local c={};for i,v in ipairs(f) do c[i]=v end;return c end
local function Carries(f,value)
 if not value then return false end
 for i=2,#f do if f[i]==value then return true end end
 return false
end
-- WLRB|sender|buildId|lastMod|idx/total|data[|requester|requestId]
local function Chunk(f)
 if f[1]~='WLRB' then return nil end
 local index,total=tostring(f[5] or ''):match('^(%d+)/(%d+)$')
 if not index then return nil end
 return {buildId=f[3],lastMod=f[4],idx=tonumber(index),total=tonumber(total),requester=f[7],requestId=f[8]}
end
-- ids.first is the crossing chunk of the dropped transfer; its exact identity
-- is requester, request ID, build, version and chunk. ids.later maps the other
-- peer's later requests to {requester, id, label}, the phase in which they
-- last crossed. Old work is linked only through the old request ID together
-- with its requester. A WLRB with that request ID from another requester, and
-- the ID with no requester field, are kept apart from it.
local function Classify(f,ids)
 local c,first=Chunk(f),ids.first
 if c and c.requestId==first.requestId and c.requester~=first.requester then return 'same-id-other-requester' end
 if c and c.requester==first.requester and c.requestId==first.requestId
  and c.buildId==first.buildId and c.lastMod==first.lastMod and c.idx>first.idx then return 'old-continuation' end
 if Carries(f,first.requestId) then
  return Carries(f,first.requester) and 'old-request' or 'same-id-unscoped'
 end
 for _,r in pairs(ids.later) do if Carries(f,r.id) and Carries(f,r.requester) then return r.label end end
 if f[1]=='WLRQ' then return 'own-request' end
 if ids.inbound and Carries(f,ids.inbound) then return 'inbound-'..tostring(f[1]) end
 if f[1]=='WLNP' then return 'presence' end
 return 'not-linkable'
end
local function Identity(f)
 local out={}
 for i=1,math.min(#f,8) do
  if not (f[1]=='WLRB' and i==6) then out[#out+1]=f[i]:sub(1,40) end
 end
 return table.concat(out,' ')
end

C.scenario('T1 Automatic -> Off with an answer in flight, then back to Automatic',function()
 local A,B=Pair.Boot({'ChoicePeer','OtherPeer'},{5,8})
 C.setup(A.e.Nexus.SyncModePolicy.Mode()=='automatic','T1: fixture: the current profile is Automatic without a choice')
 local rec=Record(A)
 C.setup(type(rec.session)=='table' and type(rec.transport)=='table' and type(rec.transport.RequestSnapshot)=='function',
  'T1: fixture: this peer\'s Sync session and transport queue are observed through pass-through recorders')
 -- This side owns a record the other side never received (its Share packets
 -- are discarded, as in sync_saved_mode_manual), so a request is answered in
 -- several chunks.
 local hidden=Pair.Post(A,'NEXUS-TEST-CHOICE-HIDDEN')
 for _=1,240 do A.H.Advance(.05,.05) end
 A.cursor=#A.H.sent
 C.setup(B.e.Nexus.BuildCatalog.Get(hidden)==nil,'T1: fixture: the other peer lacks the record')
 local switched,effect,first,firstFields,markOff=false,nil,nil,nil,nil
 local pre,tApply,offMark,probeOff=nil,nil,nil,nil
 Pair.before=function(p,q,code)
  if switched or p~=A or code~='WLRB' then return end
  local f=Fields(p.H.sent[p.cursor].text)
  local chunk=Chunk(f)
  if chunk and chunk.idx<chunk.total then
   switched,first,firstFields,markOff=true,chunk,f,#Pair.trace
   -- What the queue owns of that exact request when Off is applied.
   pre=rec.transport and chunk.requestId and rec.transport.RequestSnapshot(chunk.requester,chunk.requestId) or nil
   -- The action boundary: every record so far (the crossing send included)
   -- precedes Apply Off; every later record follows it, in this tick or later.
   tApply,offMark=A.H.now,rec.seq
   local sent0,admitted0=#A.H.sent,Stats(A).admittedPackets or 0
   local ok,result=Apply(A,'off')
   effect={ok=ok,result=result,sent=#A.H.sent-sent0,admitted=(Stats(A).admittedPackets or 0)-admitted0}
   -- Same tick, after the boundary: the recorder-boundary probe.
   probeOff=Probe(rec)
  end
 end
 local dropped0=Stats(A).modeDropped or 0
 B.e.Nexus.Sync.RequestSync()
 pcall(Pair.Until,function() return switched end,4000)
 Pair.before=nil
 C.setup(switched,'T1: fixture: the first chunk of a multi-chunk answer crossed while the rest was queued')
 if not switched then return end
 print('OBSERVED','T1 apply off',printable(effect.ok),printable(effect.result),'sent='..effect.sent,'admitted='..effect.admitted)
 C.expect(effect.ok==true and effect.result=='saved','T1: Apply Off is saved through the Store owner',printable(effect.result))
 C.expect(effect.sent==0 and effect.admitted==0,'T1: Apply itself sends and queues nothing')
 print('OBSERVED','T1 dropped transfer','build='..printable(first.buildId),'lastMod='..printable(first.lastMod),
  'chunk='..first.idx..'/'..first.total,'requester='..printable(first.requester),'request='..printable(first.requestId))
 C.setup(type(first.requestId)=='string' and first.requestId:sub(1,3)=='c1-',
  'T1: fixture: the crossing chunk carries its request identity, so later packets can be linked to it',printable(first.requestId))
 -- Classifier controls on the known chunk: the same transfer at a later index
 -- is a continuation; the same chunk under another request ID is not old work.
 local control={first=first,later={}}
 local nextChunk=Copy(firstFields);nextChunk[5]=(first.idx+1)..'/'..first.total
 local otherRequest=Copy(firstFields);otherRequest[8]='c1-fresh-control'
 C.setup(Classify(firstFields,control)=='old-request' and Classify(nextChunk,control)=='old-continuation'
  and Classify(otherRequest,control)=='not-linkable',
  'T1: fixture: the identity classifier separates the dropped transfer from other work',
  Classify(firstFields,control)..'/'..Classify(nextChunk,control)..'/'..Classify(otherRequest,control))
 -- Adversarial negatives: the same request ID, build, version and a later
 -- chunk from another requester; and the old request ID with no requester.
 local foreign=Copy(nextChunk);foreign[7]='ForeignPeer-Ebonhold'
 local unscoped={'WLXX',firstFields[2],first.requestId}
 C.setup(Classify(foreign,control)=='same-id-other-requester' and Classify(unscoped,control)=='same-id-unscoped',
  'T1: fixture: a same-ID chunk of that build from another requester is not linked to the dropped transfer, and the bare old ID is kept apart',
  Classify(foreign,control)..'/'..Classify(unscoped,control))
 -- The crossing entry through the production owners: its admission (with
 -- the caller's metadata) and its send event (the queue's own copy).
 local admitted,crossed
 for _,a in ipairs(rec.admissions) do
  if offMark and a.n<=offMark and a.queued==true and a.why==nil and Of(a.m,first.requester,first.requestId)
   and a.m.buildId==first.buildId and a.m.transferId==first.buildId then admitted=a end
 end
 for _,e in ipairs(rec.events) do
  if offMark and e.kind=='send_attempted' and e.n<=offMark and Of(e.m,first.requester,first.requestId)
   and e.m.buildId==first.buildId and e.m.chunkOrdinal==first.idx then crossed=e end
 end
 -- Recorder-boundary control: the crossing send happened in the same tick as
 -- Apply Off but before it, so it falls at or below the boundary; the probe
 -- called after Apply in that same tick falls above it, and the transport
 -- refused it without queuing.
 print('OBSERVED','T1 action boundary','mark='..printable(offMark),'apply at='..printable(tApply),
  'crossing send n='..printable(crossed and crossed.n)..' at='..printable(crossed and crossed.at),
  'probe n='..printable(probeOff and probeOff.n)..' at='..printable(probeOff and probeOff.at)
  ..' queued='..printable(probeOff and probeOff.queued)..' why='..printable(probeOff and probeOff.why))
 C.setup(offMark~=nil and crossed~=nil and crossed.n<=offMark and crossed.at==tApply
  and probeOff~=nil and probeOff.n>offMark and probeOff.at==tApply and probeOff.queued==false,
  'T1: fixture: the Apply boundary is call order. The same-tick crossing send is before it and a same-tick probe after it is recorded after it',
  printable(crossed and crossed.n)..' <= '..printable(offMark)..' < '..printable(probeOff and probeOff.n))
 local deadline=admitted and tonumber(admitted.m.expiresAt)
 print('OBSERVED','T1 crossing entry','admitted='..printable(admitted and admitted.at),'route='..printable(admitted and admitted.route),
  'chunks='..printable(admitted and admitted.chunks),'enqueuedAt='..printable(admitted and admitted.m.enqueuedAt),
  'expiresAt='..printable(deadline),'sent='..printable(crossed and crossed.at),
  'sent expiresAt='..printable(crossed and crossed.m.expiresAt),'owned at Apply='..printable(pre and pre.packets))
 C.expect(admitted~=nil and admitted.chunks==first.total and deadline~=nil
  and deadline>(tonumber(admitted.m.enqueuedAt) or math.huge) and crossed~=nil
  and crossed.m.expiresAt==deadline and crossed.at<deadline,
  'T1: the crossing chunk is the entry admitted for that exact requester, request and build, sent before its own unchanged deadline',
  printable(deadline)..' / '..printable(crossed and crossed.m.expiresAt))
 C.setup(pre~=nil and pre.packets>0 and pre.packets>=first.total-first.idx,
  'T1: fixture: when Off was applied the queue still owned the rest of that exact request',printable(pre and pre.packets))
 Pair.Advance(20)
 C.expect((Stats(A).modeDropped or 0)>dropped0,'T1: the queued rest is dropped at the existing final-submit check with the mode reason',
  (Stats(A).modeDropped or 0)-dropped0)
 -- Per entry: each remaining chunk of that exact transfer ends once, by the
 -- saved-mode decision, before its own deadline; then the queue owns nothing
 -- of the request.
 local policyA=A.e.Nexus.SyncModePolicy
 local drops,ordinals,owned={}, {}, true
 for _,e in ipairs(rec.events) do
  if offMark and e.kind=='send_dropped' and e.n>offMark and Of(e.m,first.requester,first.requestId)
   and e.m.buildId==first.buildId and e.m.transferId==first.buildId then
   drops[#drops+1]=e
   local ord=tonumber(e.m.chunkOrdinal) or 0
   ordinals[ord]=(ordinals[ord] or 0)+1
   owned=owned and policyA.IsModeReason(e.reason)==true and e.m.expiresAt==deadline and e.at<(deadline or -math.huge)
  end
 end
 local exact=#drops==first.total-first.idx
 for n=first.idx+1,first.total do exact=exact and ordinals[n]==1 end
 local after=rec.transport and first.requestId and rec.transport.RequestSnapshot(first.requester,first.requestId) or {packets=-1}
 for _,e in ipairs(drops) do
  print('OBSERVED','T1 dropped entry','chunk='..printable(e.m.chunkOrdinal)..'/'..printable(e.m.chunkTotal),'at='..printable(e.at),
   'expiresAt='..printable(e.m.expiresAt),'mode reason='..printable(policyA.IsModeReason(e.reason)))
 end
 C.expect(#drops>0 and exact and owned,
  'T1: each remaining chunk of that exact transfer ends once, dropped for the saved mode before its own deadline',
  #drops..' drop(s) of '..(first.total-first.idx))
 C.expect(after.packets==0,'T1: and then the queue owns nothing of that request',printable(after.packets))
 local sent=#A.H.sent
 Pair.Advance(20);B.e.Nexus.Sync.RequestSync();Pair.Advance(30)
 C.expect(#A.H.sent==sent,'T1: under Off nothing more is sent, and the dropped chunk is not resurrected',#A.H.sent-sent)
 C.guard(A.e.Nexus.SyncWire.Stats().suspended==false,'T1: a mode refusal never suspends the wire')
 -- Inbound handling and local records stay intact under Off.
 local received0=Stats(A).received or 0
 local inbound=Pair.Post(B,'NEXUS-TEST-CHOICE-INBOUND')
 pcall(Pair.Until,function() return (Stats(A).received or 0)>received0 end,4000)
 C.guard((Stats(A).received or 0)>received0 and A.e.Nexus.BuildCatalog.Get(hidden)~=nil,
  'T1: under Off the peer\'s Share is still received, and local records are kept',(Stats(A).received or 0)-received0)
 C.guard(#A.H.sent==sent,'T1: receiving it sent nothing',#A.H.sent-sent)
 -- Back to Automatic: Apply sends nothing. Later sends are judged by identity:
 -- none may continue the dropped transfer or answer its old request; ordinary
 -- new work (the peer's later request, this side's own new requests or fetches)
 -- is permitted and is reported by class.
 local s1,a1=#A.H.sent,Stats(A).admittedPackets or 0
 local markBack=#Pair.trace
 -- The switch-back boundary, in call order (as for Off).
 local backMark=rec.seq
 local ok,result=Apply(A,'automatic')
 C.expect(ok==true and result=='saved' and #A.H.sent==s1 and (Stats(A).admittedPackets or 0)==a1,
  'T1: Apply Automatic is saved and itself sends and queues nothing',printable(result))
 local ids={first=first,inbound=inbound,later={}}
 local function Sends()
  for i=markOff+1,#Pair.trace do
   local t=Pair.trace[i]
   if t.from==B.name and t.code=='WLRQ' then
    local id=Fields(t.text)[5]
    -- The requester as this peer's transport receives it (the sender), the
    -- form its answers carry.
    if id and id~='' then ids.later[t.from..'\0'..id]={requester=t.from,id=id,label=i>markBack and 'fresh-request' or 'off-era-request'} end
   end
  end
  local list,counts={}, {}
  for i=s1+1,#A.H.sent do
   local f=Fields(A.H.sent[i].text)
   local class=Classify(f,ids)
   list[#list+1]={class=class,fields=f}
   counts[class]=(counts[class] or 0)+1
  end
  return list,counts
 end
 Pair.Advance(10)
 local early,earlyCounts=Sends()
 for _,s in ipairs(early) do print('OBSERVED','T1 after switching back',s.class,printable(Identity(s.fields))) end
 C.expect((earlyCounts['old-continuation'] or 0)==0,
  'T1: switching back sends no continuation of the dropped transfer (same build, version and request, later chunk)',
  earlyCounts['old-continuation'] or 0)
 local function SameId(counts)
  return (counts['old-request'] or 0)+(counts['same-id-other-requester'] or 0)+(counts['same-id-unscoped'] or 0)
 end
 C.expect(SameId(earlyCounts)==0,
  'T1: and nothing else answering the request whose rest was dropped (nor carrying its ID under another or no requester)',
  SameId(earlyCounts))
 B.e.Nexus.Sync.RequestSync()
 pcall(Pair.Until,function() local _,counts=Sends();return (counts['fresh-request'] or 0)>0 end,4000)
 local all,counts=Sends()
 local fresh=0
 for _,r in pairs(ids.later) do if r.label=='fresh-request' then fresh=fresh+1 end end
 C.setup(fresh>0,'T1: fixture: the other peer\'s later request crossed after the switch back',fresh)
 C.expect((counts['fresh-request'] or 0)>0,
  'T1: a later request is answered again under its own new request identity (ordinary Automatic work)',
  counts['fresh-request'] or 0)
 C.expect((counts['old-continuation'] or 0)==0 and SameId(counts)==0,
  'T1: answering it revives no chunk of the dropped transfer and nothing under its old request',
  (counts['old-continuation'] or 0)..'/'..SameId(counts))
 -- Per entry: nothing of the old request is admitted again or attempted after
 -- Off was applied (records after the Off boundary, the same tick included),
 -- through the switch back.
 -- A refused admission attempt is not an admission; it is reported apart.
 local revived,refused=0,0
 for _,a in ipairs(rec.admissions) do
  if offMark and a.n>offMark and Of(a.m,first.requester,first.requestId) then
   if a.queued==true and a.why==nil then revived=revived+1 else refused=refused+1 end
  end
 end
 for _,e in ipairs(rec.events) do
  if offMark and e.kind=='send_attempted' and e.n>offMark and Of(e.m,first.requester,first.requestId) then revived=revived+1 end
 end
 print('OBSERVED','T1 old request after Off','admitted or attempted='..revived,'refused admission attempts='..refused)
 C.expect(revived==0,'T1: nothing of the old request is admitted again or attempted after Off (no revival of the ended entry)',revived)
 -- Fresh work on a live request: the later request's own admission after the
 -- switch back, with a later deadline than the ended entry's, and a send of
 -- that entry before its deadline.
 local freshProof,freshText=false,'none'
 for _,r in pairs(ids.later) do
  if r.label=='fresh-request' then
   for _,a in ipairs(rec.admissions) do
    local due=tonumber(a.m.expiresAt)
    if a.n>backMark and a.queued==true and a.why==nil and Of(a.m,r.requester,r.id) and due
     and due>(tonumber(a.m.enqueuedAt) or math.huge) and due>(deadline or math.huge) then
     for _,e in ipairs(rec.events) do
      if e.kind=='send_attempted' and e.n>a.n and Of(e.m,r.requester,r.id) and e.m.expiresAt==due and e.at<due then
       freshProof=true
       freshText=r.id..' admitted='..a.at..' route='..a.route..' expiresAt='..due..' sent='..e.at
      end
     end
    end
   end
  end
 end
 print('OBSERVED','T1 fresh work',freshText)
 C.expect(freshProof,'T1: the later request is fresh work: admitted after the switch back under its own identity and a later deadline, and sent before it',
  freshText)
 local summary={}
 for class,n in pairs(counts) do summary[#summary+1]=class..'='..n end
 table.sort(summary)
 print('OBSERVED','T1 sends since switching back',#all,table.concat(summary,' '))
 C.guard(#A.H.actions==0,'T1: no game action',#A.H.actions)
end)

C.scenario('T2 Manual grant: same-choice no-op keeps it; Off ends a queued request; Manual again revives nothing',function()
 local A,B=Pair.Boot({'GrantPeer','OtherPeer'},{5,8})
 local rec=Record(A)
 C.setup(type(rec.session)=='table' and type(rec.transport)=='table' and type(rec.transport.RequestSnapshot)=='function',
  'T2: fixture: this peer\'s Sync session and transport queue are observed through pass-through recorders')
 local ok,result=Apply(A,'manual')
 C.expect(ok==true and result=='saved' and A.e.Nexus.SyncModePolicy.Mode()=='manual','T2: Apply Manual is saved and honoured',printable(result))
 if not ok then return end
 Pair.Advance(10)
 local idle=#A.H.sent
 B.e.Nexus.Sync.RequestSync();Pair.Advance(20)
 C.expect(#A.H.sent==idle,'T2: under the chosen Manual an unrelated request gets no answer',#A.H.sent-idle)
 local policy=A.e.Nexus.SyncModePolicy
 A.e.SlashCmdList.NEXUS('sync')
 local grant=policy.ActiveManualGrant()
 C.setup(grant~=nil,'T2: fixture: an explicit Sync Now holds a manual grant')
 ok,result=Apply(A,'manual')
 C.expect(ok==true and result=='unchanged' and policy.ActiveManualGrant()==grant,
  'T2: applying the same stored choice is a no-op and leaves the grant as it was',printable(result))
 -- A queued request when Off is applied: the existing cancellation ends it.
 pcall(Pair.Until,function() return policy.ActiveManualGrant()==nil end,12000)
 C.setup(policy.ActiveManualGrant()==nil,'T2: fixture: the first grant ended at its own lifetime')
 local S=A.e.Nexus.Sync
 local sent=#A.H.sent
 local started=S.RequestSync()
 C.setup(started==true,'T2: fixture: a new manual Sync Now request is accepted and queued')
 -- The queued request as the production owners hold it: the session's own
 -- request identity, its queue admission and the exact request scope.
 local status0=type(rec.session)=='table' and rec.session.StatusSnapshot() or {}
 local requestId,entry=status0.requestId,nil
 for _,a in ipairs(rec.admissions) do
  if requestId and a.m.requestId==requestId and a.m.queueClass=='request' and a.queued==true and a.why==nil then entry=a end
 end
 local requester=entry and entry.m.requester
 local due=entry and tonumber(entry.m.expiresAt)
 local grant2=policy.ActiveManualGrant()
 local function Owned()
  if not (type(rec.transport)=='table' and requester and requestId) then return -1 end
  return rec.transport.RequestSnapshot(requester,requestId).packets
 end
 local owned0=Owned()
 print('OBSERVED','T2 queued request','request='..printable(requestId),'requester='..printable(requester),
  'route='..printable(entry and entry.route),'grant='..printable(entry and entry.m.manualGrant)..'/'..printable(grant2),
  'enqueuedAt='..printable(entry and entry.m.enqueuedAt),'expiresAt='..printable(due),'owned='..owned0)
 C.expect(entry~=nil and grant2~=nil and entry.m.manualGrant==grant2 and due~=nil
  and due>(tonumber(entry.m.enqueuedAt) or math.huge) and owned0==1 and status0.requestQueued==true,
  'T2: the queued request is one queue entry of its own request, carrying the active grant and its own deadline',
  printable(entry and entry.m.manualGrant)..' / '..owned0)
 -- The Off boundary, in call order: the request's own admission (same tick
 -- as Apply Off) is at or below it; anything recorded after Apply is above it.
 local offMark,tOff=rec.seq,A.H.now
 ok,result=Apply(A,'off')
 C.expect(ok==true and result=='saved' and #A.H.sent==sent,'T2: Apply Off is saved and itself sends nothing',printable(result))
 -- Recorder-boundary control, same tick: the request's admission falls at
 -- or below the boundary, and the probe called after Apply falls above it
 -- (refused by the transport without queuing).
 local probeOff=Probe(rec)
 print('OBSERVED','T2 action boundary','mark='..offMark,'apply at='..printable(tOff),
  'admission n='..printable(entry and entry.n)..' at='..printable(entry and entry.at),
  'probe n='..printable(probeOff and probeOff.n)..' at='..printable(probeOff and probeOff.at)
  ..' queued='..printable(probeOff and probeOff.queued)..' why='..printable(probeOff and probeOff.why))
 C.setup(entry~=nil and entry.n<=offMark and entry.at==tOff
  and probeOff~=nil and probeOff.n>offMark and probeOff.at==tOff and probeOff.queued==false,
  'T2: fixture: the Off boundary is call order. The same-tick request admission is before it and a same-tick probe after it is recorded after it',
  printable(entry and entry.n)..' <= '..offMark..' < '..printable(probeOff and probeOff.n))
 -- The same twenty seconds as before (400 steps of 0.05 s), with a read-only
 -- look at the exact request scope after each step.
 local ended=nil
 for _=1,math.floor(20/.05+.5) do
  Pair.Step()
  if not ended and Owned()==0 then ended=A.H.now end
 end
 C.expect(#A.H.sent==sent,'T2: the queued request is not submitted under Off',#A.H.sent-sent)
 C.expect(policy.ActiveManualGrant()==nil and Stats(A).terminalReason=='sync_mode',
  'T2: the operation ended through the existing cancellation with the sync-mode reason',printable(Stats(A).terminalReason))
 -- Per entry: it left the queue unattempted, before its own deadline. If the
 -- final-submit check met it first, that drop carries the mode reason, its
 -- grant and its deadline. Otherwise the only route left in SyncTransport for
 -- an unattempted request packet before its deadline is the cancelled-request
 -- cleanup (PruneQueue/StaleReason "superseded"), which emits no per-packet event.
 local attempted,dropped=0,nil
 for _,e in ipairs(rec.events) do
  if requester and Of(e.m,requester,requestId) then
   if e.kind=='send_attempted' then attempted=attempted+1 end
   if e.kind=='send_dropped' then dropped=e end
  end
 end
 local status1=type(rec.session)=='table' and rec.session.StatusSnapshot() or {}
 print('OBSERVED','T2 request end','left queue='..printable(ended),'after Off='..printable(ended and ended-tOff),
  'deadline='..printable(due),'attempted='..attempted,
  'route='..(dropped and 'mode drop at submission' or 'cancelled-request cleanup'),
  'session='..printable(status1.queueOutcome)..'/'..printable(status1.terminalReason))
 C.expect(ended~=nil and due~=nil and ended<due and attempted==0 and status1.requestQueued==false
  and status1.converging==false and status1.queueOutcome=='dropped'
  and (dropped==nil or (policy.IsModeReason(dropped.reason)==true and dropped.m.manualGrant==grant2
   and dropped.m.expiresAt==due)),
  'T2: that exact entry leaves the queue unattempted before its own deadline, ended by the session\'s mode cancellation',
  printable(ended)..' < '..printable(due))
 ok,result=Apply(A,'manual')
 Pair.Advance(10)
 C.expect(ok==true and policy.ActiveManualGrant()==nil and #A.H.sent==sent,
  'T2: applying Manual again revives no grant and sends nothing',printable(result))
 -- Admissions after the Off boundary (the same tick included) under that
 -- request ID.
 local again=0
 for _,a in ipairs(rec.admissions) do
  if requestId and a.m.requestId==requestId and a.n>offMark and a.queued==true and a.why==nil then again=again+1 end
 end
 C.expect(again==0 and Owned()==0,'T2: and admits nothing under the ended request (no revival of that entry)',again..' / '..Owned())
 C.guard(A.e.NexusDB.settingsVersion==2,'T2: the profile marker is unchanged',printable(A.e.NexusDB.settingsVersion))
 C.guard(#A.H.actions==0,'T2: no game action',#A.H.actions)
end)

-- D2/D3 characterization of existing pending-login behavior. These are
-- GUARDs on f1b0a726: Apply itself sends nothing, while the ordinary scheduler
-- can later start a login request retained under Manual or Off.
for _,bootMode in ipairs({'manual','off'}) do
 C.scenario('D23 '..bootMode..' boot -> Automatic retains pending login',function()
  local A=Pair.Boot({'Modewaiter','Quietpeer'},{0,0},function(i,db)
   db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode=i==1 and bootMode or 'off'
  end)
  local e=A.e
  C.setup(e.Nexus.SyncModePolicy.Mode()==bootMode,'D23 '..bootMode..': fresh boot uses saved mode')
  local sent=#A.H.sent
  Pair.Advance(40)
  C.guard(#A.H.sent==sent,'D23 '..bootMode..': no click and no outgoing login request under saved mode')
  e.Nexus.CommunityBuilds.Show()
  local f=e.NexusCommunityBuildsFrame
  C.setup(f and f._modeBtn,'D23 '..bootMode..': real mode button exists')
  local admitted=Stats(A).admittedPackets or 0
  if f and f._modeBtn then f._modeBtn:Click() end
  local d=e.NexusSyncModeDialog
  C.setup(d and d:IsShown(),'D23 '..bootMode..': real draft opens')
  if d and d.cancel then d.cancel:Click() end
  C.guard(#A.H.sent==sent and (Stats(A).admittedPackets or 0)==admitted
   and e.Nexus.SyncModePolicy.Mode()==bootMode and e.NexusDB.settings.nexusSyncModeChoice==nil,
   'D23 '..bootMode..': opening and dismissing the draft changes and sends nothing')
  local ok,result=Apply(A,'automatic')
  C.guard(ok==true and result=='saved' and #A.H.sent==sent
   and (Stats(A).admittedPackets or 0)==admitted,
   'D23 '..bootMode..': Apply Automatic only saves the choice; no immediate send or queue admission',result)
  Pair.Advance(40)
  local requests=0
  for i=sent+1,#A.H.sent do
   local fields=Fields(A.H.sent[i].text)
   if fields[1]=='WLRQ' and e.Nexus.Identity.SamePlayer(fields[2],A.name) then requests=requests+1 end
  end
  C.guard(requests>0,'D23 '..bootMode..': ordinary scheduler later emits the retained login request',requests)
  C.guard(#A.H.actions==0,'D23 '..bootMode..': no game action',#A.H.actions)
 end)
end

C.finish('(applied choices change later sending only through the existing admission and final-submit paths)')
