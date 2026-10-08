-- Receiver batching: the items waiting when the catalog becomes free are
-- committed by ONE catalog mutation with frozen membership. Each member keeps
-- its own validation, ticket, storage answer and refusal reason, the bounds
-- count queued plus in-flight items, a cancelled candidate commits nothing,
-- and the capacity limits are unchanged. Real TOC, real inbound decoder, real
-- receiver admission, real catalog.
local A=dofile('tests/prototype/sync_admission_support.lua');local T=A.T
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Snapshot() return Nexus.Sync.AdmissionSnapshot() end
local function Stats() return Nexus.Sync.Stats() end
local function Serialize(v,parents)
 if type(v)~='table' then return tostring(v) end
 parents=parents or {};assert(not parents[v]);parents[v]=true
 local keys={};for k in pairs(v)do keys[#keys+1]=tostring(k) end
 table.sort(keys)
 local out={}
 for _,k in ipairs(keys)do
  local value=v[k];if value==nil then value=v[tonumber(k)] end
  out[#out+1]=k..'='..Serialize(value,parents)
 end
 parents[v]=nil
 return '{'..table.concat(out,',')..'}'
end

-- 1. Many waiting items are committed by one batch, each settled exactly once.
local H,C=A.Boot(60)
A.Hold(C)
local ids={}
for i=1,8 do
 local id='batch-'..i;ids[#ids+1]=id
 A.Receive(id,'Peer'..i,A.base+10+i,'Batch record '..i)
end
check(Snapshot().count==8,'eight valid records wait while the catalog is busy: '..Snapshot().count)
check(Snapshot().inFlight==0,'nothing is in flight yet')
T.Until(H,function()return C.Get('batch-8')~=nil end)
check(#H.batches>=1,'the waiting items were submitted as a batch: '..#H.batches)
local first=H.batches[1]
check(first.members>1 and first.accepted,'the first batch carried several members: '..first.members)
for _,id in ipairs(ids)do
 check(C.Get(id)~=nil,id..' is committed')
 check(H.puts[id].accepted==1,id..': exactly one accepted submission')
 check(H.puts[id].batched>=1,id..': it was submitted inside a batch')
end
A.Settled(H,C)
check(Snapshot().count==0 and Snapshot().inFlight==0,'the owner ends empty')
check((Stats().admissionExpired or 0)==0 and (Stats().storageRejected or 0)==0,
 'no waiting item was lost')

-- 2. An arrival during an active batch waits for a later batch.
H,C=A.Boot(60)
A.Hold(C)
for i=1,4 do A.Receive('early-'..i,'Peer'..i,A.base+10+i,'Early '..i) end
T.Until(H,function()return Snapshot().inFlight>0 end)
local frozen=Snapshot().inFlight
check(frozen==4,'the frozen batch holds the four waiting items: '..frozen)
A.Receive('late-1','PeerLate',A.base+30,'Late arrival')
check(Snapshot().count==1,'the later arrival waits in the queue instead of joining: '..Snapshot().count)
check(Snapshot().inFlight==frozen,'the running batch did not grow: '..Snapshot().inFlight)
T.Until(H,function()return C.Get('late-1')~=nil end)
check(#H.batches>=2,'the later arrival was committed by a further batch: '..#H.batches)
A.Settled(H,C)

-- 3. The bounds count queued and in-flight items together.
H,C=A.Boot(60)
A.Hold(C)
for i=1,16 do A.Receive('fair-'..i,'Crowd',A.base+10+i,'Crowd record '..i) end
check(Snapshot().count==16,'the per-sender bound admits sixteen: '..Snapshot().count)
local overflowBefore=Stats().admissionOverflow or 0
A.Receive('fair-17','Crowd',A.base+40,'Seventeenth record')
check((Stats().admissionOverflow or 0)==overflowBefore+1,'the seventeenth is a counted refusal')
T.Until(H,function()return Snapshot().inFlight>0 end)
check(Snapshot().inFlight==16 and Snapshot().count==0,
 'all sixteen moved into the candidate: '..Snapshot().inFlight..'/'..Snapshot().count)
overflowBefore=Stats().admissionOverflow or 0
A.Receive('fair-18','Crowd',A.base+41,'Eighteenth record')
check((Stats().admissionOverflow or 0)==overflowBefore+1,
 'an in-flight member still counts against its sender bound')
A.Settled(H,C)

-- 4. The catalog contract itself: mixed members, bounds and empty requests.
H,C=A.Boot(20)
local okEmpty,whyEmpty=C.PutBatch({})
check(okEmpty==false and whyEmpty=='empty batch','an empty batch is refused: '..tostring(whyEmpty))
local big={}
for i=1,65 do big[i]={record={id='big-'..i,title='Big '..i,author='A',class='MAGE',
 lastModified=1,postedAt=1,echoes={},echoCount=0},options={source='remote'}} end
local okBig,whyBig=C.PutBatch(big)
check(okBig==false and whyBig=='BATCH_TOO_LARGE','a batch above the bound is refused: '..tostring(whyBig))
local valid={id='mixed-valid',title='Mixed valid',author='Peer-Ebonhold',class='MAGE',
 lastModified=A.base+5,postedAt=A.base+5,echoes={},echoCount=0,
 ownerKey=Nexus.Identity.OwnerKey('Peer','Ebonhold'),fingerprintHash='a1',ownerVerified=true}
local mixed={{record=valid,options={source='remote',sender='Peer-Ebonhold'}},
 {record={title='No identity'},options={source='remote',sender='Peer-Ebonhold'}}}
local okMixed,whyMixed,tickets=C.PutBatch(mixed)
check(okMixed==nil and whyMixed=='ROOT_MUTATION_PENDING' and type(tickets)=='table' and #tickets==2,
 'a mixed batch returns one ticket per request: '..tostring(whyMixed))
T.Until(H,function()return tickets[1].state~='pending' and tickets[2].state~='pending' end)
check(tickets[1].committed==true,'the valid member is committed: '..tostring(tickets[1].reason))
check(tickets[2].committed==false and tickets[2].reason=='build id required',
 'the invalid member keeps its own refusal: '..tostring(tickets[2].reason))
check(C.Get('mixed-valid')~=nil,'the valid member reached the catalog')

-- 5. A cancelled candidate commits nothing and settles every member.
H,C=A.Boot(60)
A.Hold(C)
for i=1,5 do A.Receive('cancel-'..i,'PeerC'..i,A.base+10+i,'Cancel '..i) end
T.Until(H,function()return Snapshot().inFlight>0 end)
local before=Serialize(NexusDB.communityBuilds)
local rejectedBefore=Stats().storageRejected or 0
C.CancelRootAdmission()
H.Advance(1,.05)
check(Snapshot().inFlight==0,'the cancelled members left the in-flight accounting')
for i=1,5 do check(C.Get('cancel-'..i)==nil,'cancel-'..i..' was not committed') end
check((Stats().storageRejected or 0)>=rejectedBefore+5,
 'each cancelled member settled as a counted storage refusal: '
 ..tostring((Stats().storageRejected or 0)-rejectedBefore))
check(Serialize(NexusDB.communityBuilds)==before,'the saved Community data is unchanged')

-- 6. Without a usable clock the drive keeps its single slice per update.
H,C=A.Boot(60)
local realClock=debugprofilestop
debugprofilestop=nil
A.Hold(C)
for i=1,4 do A.Receive('slow-'..i,'PeerS'..i,A.base+10+i,'Slow '..i) end
local worst,previous=0,C.ManualPreparationStatus().totalPumps
for _=1,600 do
 H.Advance(1/60,1/60)
 local now=C.ManualPreparationStatus().totalPumps
 if now-previous>worst then worst=now-previous end
 previous=now
end
debugprofilestop=realClock
check(worst<=2,'a missing clock keeps the safe single slice per update: '..worst)

-- 6b. One item whose own submission raises must not starve the valid items
-- behind it: it is reported, retried once and then refused with a counted
-- outcome, while every other retained item is still committed.
local function ErrorRun(persistent)
 local H,C=A.Boot(60)
 A.Hold(C)
 local ids={}
 for i=1,5 do ids[#ids+1]='err-'..i;A.Receive('err-'..i,'PeerE'..i,A.base+10+i,'Error case '..i) end
 check(Nexus.Sync.AdmissionSnapshot().count==5,'five items wait: '..Nexus.Sync.AdmissionSnapshot().count)
 local raised,get=0,C.Get
 C.Get=function(id,...)
  if id=='err-3' and (persistent or raised==0) then
   raised=raised+1
   error('synthetic admission failure for '..tostring(id),0)
  end
  return get(id,...)
 end
 T.Until(H,function()return Nexus.Sync.AdmissionSnapshot().count==0
  and (tonumber(Nexus.Sync.AdmissionSnapshot().inFlight) or 0)==0 end,40000)
 H.Advance(5,.05)
 C.Get=get
 local committed=0
 for _,id in ipairs(ids)do if C.Get(id)~=nil then committed=committed+1 end end
 return committed,raised,Nexus.Sync.Stats()
end
do
 local committed,raised,stats=ErrorRun(false)
 check(raised>=1,'one-shot: the synthetic failure really happened')
 check(committed==5,'one-shot: every retained item was still committed: '..committed..'/5')
 check((stats.admissionExpired or 0)==0,'one-shot: nothing expired waiting behind it')
end
do
 local committed,raised,stats=ErrorRun(true)
 check(raised>=2,'persistent: the failure repeated: '..raised)
 check(committed==4,'persistent: the four valid items were committed: '..committed..'/5')
 check((stats.storageRejected or 0)>=1,'persistent: the failing item ended as a counted refusal')
 check((stats.admissionExpired or 0)==0,'persistent: no valid item expired behind the failing one')
end

-- 7. The build limit holds: a record for a new build identity is refused when
-- the catalog already holds 2048, before any catalog mutation (no candidate, no
-- futile mutation), explicitly, and the published root stays as it is.
H,C=A.Boot(2048)
A.Receive('admission-holder','Holder',A.base)
A.Receive('overflow-1','PeerO',A.base+50,'Beyond capacity')
T.Until(H,function()return (Stats().storageRejected or 0)>=2 or C.Get('overflow-1')~=nil end)
check(C.Get('overflow-1')==nil and C.Get('admission-holder')==nil,'no record beyond the build limit is committed')
local rows=0;for _ in pairs(NexusDB.communityBuilds)do rows=rows+1 end
check(rows==2048,'the saved overlay did not grow past the limit: '..rows)
check(H.puts['overflow-1'] and H.puts['overflow-1'].lastRefusal=='ROOT_SLOT_LIMIT',
 'the refusal is explicit: '..tostring(H.puts['overflow-1'] and H.puts['overflow-1'].lastRefusal))
local full=C.SaturationSummary()
check(full and full.reason=='ROOT_SLOT_LIMIT' and full.counter=='distinct-builds'
 and full.limit==2048 and full.refused>=2,'the refusals are retained as saturation facts')
check(C.ManualPreparationStatus().ready and #H.batches==0,
 'no catalog candidate was started for them: batches='..#H.batches)
check(Nexus.StartupStatus().state=='ready' and C.Status().availableCount==2048,
 'the admitted catalog stays available with all 2048 builds')
print('PASS sync_admission_batch: one frozen batch per ready turn; per-member outcomes, bounds, cancellation, clock fallback; a full catalog refuses new builds before any mutation checks='..checks)
