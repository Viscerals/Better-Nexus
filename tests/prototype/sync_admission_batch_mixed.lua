-- A receiver queue holds two kinds of item: summaries and full records. Both
-- must survive the same ready turn. A full record that takes the catalog for
-- itself must not cause the summaries collected in that turn to be refused:
-- they belong to a later batch, with their own unchanged deadlines.
-- Real TOC on two runtimes, real transport, real decoder, real catalog.
-- Disclosed limit: this fixture exercises the mixed queue end to end, but it
-- does not reproduce the exact interleaving in which a full record takes the
-- catalog in the middle of one collection pass. Reverting the three defences
-- (the collector branch for full records, the readiness recheck inside the
-- pass, and the requeue when a batch cannot start) leaves this test green, so
-- it is a regression guard for the mixed queue, not proof of that ordering.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local A,B=P.Boot({'MixAlpha','MixBeta'})
local function Snapshot() return B.e.Nexus.Sync.AdmissionSnapshot() end
local function Stats() return B.e.Nexus.Sync.Stats() end
local function Kinds()
 local summary,build=0,0
 for _,row in ipairs(Snapshot().entries)do
  if row.kind=='build' then build=build+1 else summary=summary+1 end
 end
 return summary,build
end
local ids,injected={},false
local function Summary(id,name,stamp)
 local sender=name..'-Ebonhold'
 local data={id=id,t='Mixed '..id,a=sender,o=B.e.Nexus.Identity.OwnerKey(name,'Ebonhold'),
  c='MAGE',m=stamp,h='a1',n=3}
 B.e.Nexus.Sync.HandleIncoming('WLBI|'..sender..'|'
  ..B.e.Nexus.Codec.Base64Encode(B.e.Nexus.Codec.JSONEncode(data)),sender)
 return id
end
-- The full record of A's build reaches B as WLRB chunks. Just before the last
-- chunk is delivered, B is made busy and four summaries are retained, so the
-- assembled full record joins the same queue as those summaries.
P.before=function(p,q,code)
 if injected or p~=A or q~=B or code~='WLRB' then return end
 if not P.Ready(B) then return end
 injected=true
 local C=B.e.Nexus.BuildCatalog
 local seed=C.Get('synthetic-startup-1')
 if not seed then injected=false;return end
 local row=B.H.Clone(seed)
 row.id='mixed-holder';row.title='Holder'
 row.lastModified=(tonumber(row.lastModified) or 1)+1
 local ok,why,ticket=C.PutDeferred(row)
 assert(ok==nil and why=='ROOT_MUTATION_PENDING' and type(ticket)=='table',
  'fixture: B really holds a catalog transaction: '..tostring(why))
end

local shared=P.Post(A,'NEXUS-TEST-MIXED-QUEUE')
-- The full record must be FIRST in the queue: its own submission takes the
-- catalog, and the summaries behind it must survive that turn.
P.Until(function()local _,builds=Kinds();return injected and builds>=1 end,12000)
local summaryCount,buildCount=Kinds()
check(buildCount>=1,'the assembled full record is retained first: '..buildCount)
for index=1,4 do ids[#ids+1]=Summary('mixed-'..index,'MixPeer'..index,1000+index) end
summaryCount,buildCount=Kinds()
check(summaryCount>=4 and buildCount>=1,
 'four summaries wait behind the full record: '..summaryCount..'/'..buildCount)

-- Let every retained item settle. Nothing may be refused or lost.
P.Until(function()
 return Snapshot().count==0 and (tonumber(Snapshot().inFlight) or 0)==0
end,30000)
for _,id in ipairs(ids)do
 check(B.e.Nexus.BuildCatalog.Get(id)~=nil,id..' was committed, not refused')
end
check(P.Full(B,shared)~=nil,'the full record was stored as well')
check((Stats().storageRejected or 0)==0,
 'no retained item was reported as a storage failure: '..tostring(Stats().storageRejected))
check((Stats().admissionExpired or 0)==0,
 'no retained item expired: '..tostring(Stats().admissionExpired))
P.Until(function()
 return Snapshot().count==0 and (tonumber(Snapshot().inFlight) or 0)==0
end,20000)
check(Snapshot().count==0 and (tonumber(Snapshot().inFlight) or 0)==0,'the receiver owner drains completely')
print('PASS sync_admission_batch_mixed: a full record and summaries share one queue; every retained item is committed, none refused or lost checks='..checks)
