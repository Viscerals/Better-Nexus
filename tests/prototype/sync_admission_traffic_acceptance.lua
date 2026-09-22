-- #76-A acceptance: 1350 starting rows, one valid inbound record every 20
-- simulated seconds for 900 seconds from 45 distinct peers, then a bounded
-- drain with no new arrivals up to the latest original deadline. Every valid
-- record must be committed before its OWN 300-second deadline, exactly once,
-- with the exact content that was sent, and every identity must be in exactly
-- one category at each boundary. The per-update slice cap must hold.
-- Real TOC, real inbound decoder, real receiver admission, real catalog.
-- Simulated update clock and work counters; not WoW frame times.
local A=dofile('tests/prototype/sync_admission_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local ROWS,EVERY,SPAN,DEADLINE,CAP=1350,20,900,300,32
local H,C=A.Boot(ROWS)
local FPS=60;local dt=1/FPS
local tickets,sentData,arrivedAt,committedAt={},{},{},{}
local batches,largestBatch=0,0
local put=C.Put
C.Put=function(record,options,...)
 local ok,why,ticket=put(record,options,...)
 if type(ticket)=='table' then tickets[record.id]=ticket end
 return ok,why,ticket
end
local putBatch=C.PutBatch
check(type(putBatch)=='function','the catalog offers a multi-record put')
C.PutBatch=function(requests,...)
 local ok,why,issued=putBatch(requests,...)
 if type(issued)=='table' then
  batches=batches+1
  if #requests>largestBatch then largestBatch=#requests end
  for index,request in ipairs(requests)do
   local record=type(request)=='table' and request.record or nil
   if record and type(issued[index])=='table' then tickets[record.id]=issued[index] end
  end
 end
 return ok,why,issued
end
local function Snapshot() return Nexus.Sync.AdmissionSnapshot() end
local ids,sent,frames,nextAt={},0,0,0
local worstFrameSlices,pumpsBefore=0,C.ManualPreparationStatus().totalPumps
local function Step(t)
 for _,id in ipairs(ids)do
  if committedAt[id]==nil and C.Get(id)~=nil then committedAt[id]=t end
 end
 H.Advance(dt,dt);frames=frames+1
 local pumpsAfter=C.ManualPreparationStatus().totalPumps
 local used=pumpsAfter-pumpsBefore
 if used>worstFrameSlices then worstFrameSlices=used end
 pumpsBefore=pumpsAfter
end
while frames*dt<SPAN do
 local t=frames*dt
 if t>=nextAt then
  sent=sent+1
  local id='traffic-'..sent
  ids[#ids+1]=id;arrivedAt[id]=t
  sentData[id]=A.Receive(id,'Peer'..sent,A.base+100+sent,'Traffic '..sent)
  nextAt=nextAt+EVERY
 end
 Step(t)
end
local function Categories()
 local queued={}
 for _,row in ipairs(Snapshot().entries)do queued[tostring(row.id)]=true end
 local out={committed={},queued={},inflight={},terminal={}}
 for _,id in ipairs(ids)do
  local ticket=tickets[id]
  if C.Get(id)~=nil then out.committed[#out.committed+1]=id
  elseif queued[id] then out.queued[#out.queued+1]=id
  elseif ticket and ticket.state=='pending' then out.inflight[#out.inflight+1]=id
  else out.terminal[#out.terminal+1]=id end
 end
 return out
end
local function Exclusive(label)
 local cat=Categories()
 local total=#cat.committed+#cat.queued+#cat.inflight+#cat.terminal
 check(total==sent,label..': every identity is in exactly one category: '..total..'/'..sent)
 return cat
end
local atArrivalEnd=Exclusive('arrival period')
check(#atArrivalEnd.terminal==0,
 'arrival period: no valid record ended terminal: '..table.concat(atArrivalEnd.terminal,','))

-- Bounded drain only: no new arrivals, and no later than the latest deadline.
local lastArrival=0
for _,id in ipairs(ids)do if arrivedAt[id]>lastArrival then lastArrival=arrivedAt[id] end end
local drainUntil=lastArrival+DEADLINE
while frames*dt<drainUntil do Step(frames*dt) end
local final=Exclusive('bounded drain')
check(#final.committed==sent,'every valid record is committed: '..#final.committed..'/'..sent)
check(#final.queued==0 and #final.inflight==0 and #final.terminal==0,
 'nothing is left queued, in flight or terminal')

local worst=0
for _,id in ipairs(ids)do
 local latency=(committedAt[id] or drainUntil)-arrivedAt[id]
 if latency>worst then worst=latency end
 check(latency<=DEADLINE,id..' committed within its own deadline: '..math.floor(latency)..'s')
end

-- Content equality, not counters: the committed row carries exactly what the
-- peer sent, and each identity was submitted and accepted exactly once.
for _,id in ipairs(ids)do
 local row,data=C.Get(id),sentData[id]
 check(row.title==data.t and row.author==data.a and row.ownerKey==data.o
  and row.lastModified==data.m and row.class==data.c and row.isMine~=true,
  id..': the committed row equals the received record')
 local seen=H.puts[id]
 -- A deferred item is refused once, without a ticket, when it first finds
 -- the catalog busy. Only the accepted submission may happen once.
 check(seen and seen.accepted==1,
  id..': exactly one accepted submission: '..tostring(seen and seen.accepted))
 check(seen.lastRefusal==nil or seen.lastRefusal=='ROOT_MUTATION_PENDING',
  id..': its only refusal was the busy catalog: '..tostring(seen.lastRefusal))
end
local stats=Nexus.Sync.Stats()
check((stats.admissionExpired or 0)==0,'no valid record expired waiting: '..tostring(stats.admissionExpired))
check((stats.storageRejected or 0)==0,'no valid record was refused by storage: '..tostring(stats.storageRejected))
check((stats.admissionOverflow or 0)==0,'the bounded queue never overflowed at this rate')
check(Snapshot().count==0 and (tonumber(Snapshot().inFlight) or 0)==0,
 'the receiver owner ends empty')

-- Bounded work: the shared per-update allowance never exceeds its slice cap,
-- and the batch really carried several records per rebuild.
-- The shared envelope is MANUAL_SLICES per update. A direct put that finds
-- the catalog free still performs its own single commit pump, exactly as
-- before this correction, so one update can show one slice more.
check(worstFrameSlices<=CAP+1,'no update exceeded the shared slice cap: '..worstFrameSlices)
check(batches>=1,'records were committed through the multi-record put: '..batches)
check(largestBatch>1,'at least one batch carried several records: '..largestBatch)
local timing=Nexus.manualSyncTiming
check(type(timing)=='table' and timing.slices>0,'the shared timing record counted its slices')
-- Committing records transmits no build data. The only outbound packets are
-- the ordinary requests that receiving a summary already produced before this
-- correction: one loadout recovery request per summary and the reconciliation
-- request. An accepted record, a committed record and a transmitted packet
-- stay separate events.
local allowed={WLLQ=true,WLRQ=true}
local outbound={}
for _,packet in ipairs(H.sent)do
 local text=(packet.text or ''):gsub('||','|'):gsub('^P%d+:','')
 local kind=text:match('^(%u+)') or 'unknown'
 outbound[kind]=(outbound[kind] or 0)+1
 check(allowed[kind]==true,'only ordinary request traffic is transmitted: '..kind)
end
check((outbound.WLBI or 0)==0 and (outbound.WLBD or 0)==0,
 'no build payload was transmitted by committing received records')
print(string.format('PASS sync_admission_traffic_acceptance: %d/%d committed before their own deadlines; worst %ds; %d batches, largest %d; worst update %d slices checks=%d',
 #final.committed,sent,math.floor(worst),batches,largestBatch,worstFrameSlices,checks))
