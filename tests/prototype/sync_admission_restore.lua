-- A receiver batch that cannot start must not settle its members. They were
-- collected out of the queue, so if the catalog refuses the batch itself, the
-- members have to go back to the queue with their own places and their own
-- unchanged deadlines, and be committed by a later batch. Settling them there
-- would lose valid records that were still inside their lifetime, which is the
-- data-loss class the #76-A review found. The refusal is injected at the
-- catalog entry point the support already wraps; no product code is changed
-- and no private state is touched.
-- Scope: this drives the restore that follows a refused submission. The other
-- restore, the one after a collection pass that cannot complete, is not
-- reachable from outside and is NOT covered here.
local A=dofile('tests/prototype/sync_admission_support.lua');local T=A.T
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Snapshot() return Nexus.Sync.AdmissionSnapshot() end
local function Stats() return Nexus.Sync.Stats() end

local H,C=A.Boot(60)
A.Hold(C)
local ids={}
for i=1,5 do
 local id='restore-'..i;ids[#ids+1]=id
 A.Receive(id,'Peer'..i,A.base+10+i,'Restore record '..i)
end
check(Snapshot().count==5,'five valid records wait while the catalog is busy: '..Snapshot().count)
local rejectedBefore=Stats().storageRejected or 0
local expiredBefore=Stats().admissionExpired or 0

-- While the catalog refuses the batch itself, no member may be settled.
local realPutBatch=C.PutBatch
local refused,blocking=0,true
C.PutBatch=function(requests,...)
 if blocking then
  refused=refused+1
  return false,'BATCH_TOO_LARGE'
 end
 return realPutBatch(requests,...)
end
-- Bounded, and tolerant of not reaching three refusals: a member that was
-- wrongly settled shows up as an empty queue in the checks below instead of as
-- a timeout with no explanation. A drive that stops offering batches empties
-- the queue the same way, through expiry, so read the expiry counter below
-- before concluding that a member was settled.
pcall(T.Until,H,function()return refused>=3 end,20000)
check(refused>=1,'the drive offered at least one batch and the catalog refused it: '..refused)
check(Snapshot().count==5,'every collected member went back to the queue: '..Snapshot().count)
check(Snapshot().inFlight==0,'and none of them stayed in flight: '..Snapshot().inFlight)
check((Stats().storageRejected or 0)==rejectedBefore,
 'no member was settled as a storage failure: '
 ..tostring((Stats().storageRejected or 0)-rejectedBefore))
check((Stats().admissionRestored or 0)>=5,'the restore is counted: '..tostring(Stats().admissionRestored))
for _,id in ipairs(ids)do check(C.Get(id)==nil,id..' is not committed while the catalog refuses the batch') end
blocking=false
-- The stub is removed as soon as it has done its work, so a later failure
-- cannot leave it installed.
C.PutBatch=realPutBatch

-- A later batch commits all of them, inside their own unchanged lifetime.
T.Until(H,function()return C.Get('restore-5')~=nil end)
for _,id in ipairs(ids)do
 check(C.Get(id)~=nil,id..' is committed by a later batch')
 check(H.puts[id].accepted==1,id..': exactly one accepted submission')
end
check((Stats().admissionExpired or 0)==expiredBefore,'no waiting record expired while it was restored')
A.Settled(H,C)
check(Snapshot().count==0 and Snapshot().inFlight==0,'the owner ends empty')
print('PASS sync_admission_restore: a refused batch returns its members to the queue and they are committed later checks='..checks)
