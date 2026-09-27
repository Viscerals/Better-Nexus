-- The manual-request hold covers the full-record consumer too. A real full
-- record arrives at a receiver whose explicit Sync Now is accepted and unsent:
-- it is retained by the scoped deferred owner, the request is transmitted
-- first, and the exact record then settles through the ordinary pump.
local P=dofile('tests/prototype/sync_pair_support.lua')
local A,B=P.Boot({'ReadyAlpha','ReadyBeta'},5)
local C=B.e.Nexus.BuildCatalog
local function Stats()return B.e.Nexus.Sync.Stats()end
local full={calls=0,accepted=0}
-- Transmission is the hand-off to the client send API, which the harness
-- captures in H.sent. The pair bridge delivers a packet (P.trace) only after
-- both peers advanced in the same step, and the sender's update submits
-- deferred work after its transport turn, so the held record may be submitted
-- in the same update just after the request left. The order is therefore
-- checked at the send boundary, not at delivery.
local heldId,sentAtClick,heldSubmissions,submittedBeforeRequest=nil,nil,0,false
local function RequestSentSince(mark)
 for i=mark+1,#B.H.sent do
  local code=B.H.sent[i].text:gsub('||','|'):match('^([^|]+)'):gsub('^P%d+:','')
  if code=='WLRQ' then return true end
 end
 return false
end
local function Submitted(row)
 if heldId==nil or sentAtClick==nil or row.id~=heldId then return end
 heldSubmissions=heldSubmissions+1
 if not RequestSentSince(sentAtClick) then submittedBeforeRequest=true end
end
local put=C.Put
C.Put=function(row,options,...)   -- observe only
 if type(row)=='table' then Submitted(row) end
 local ok,why,ticket=put(row,options,...)
 if type(row.echoes)=='table' and #row.echoes>0 then
  full.calls=full.calls+1
  if ok==true or (ok==nil and type(ticket)=='table')then full.accepted=full.accepted+1 end
 end
 return ok,why,ticket
end
-- A record committed inside a receiver batch is recorded exactly like a
-- single put, so the counts below keep their meaning on both routes.
local putBatch=C.PutBatch
if type(putBatch)=='function' then
 C.PutBatch=function(requests,...)
  for _,request in ipairs(requests or {})do
   if type(request)=='table' and type(request.record)=='table' then Submitted(request.record) end
  end
  local ok,why,tickets=putBatch(requests,...)
  for index,request in ipairs(requests or {})do
   local row=type(request)=='table' and request.record or nil
   if row and type(row.echoes)=='table' and #row.echoes>0 then
    full.calls=full.calls+1
    if type(tickets)=='table' and type(tickets[index])=='table' then
     full.accepted=full.accepted+1
    end
   end
  end
  return ok,why,tickets
 end
end
local clicked,requestsBefore,heldBefore,callsAtArrival=false,0,0,nil
local function Requests()
 local n=0;for _,packet in ipairs(P.trace)do if packet.from==B.name and packet.code=='WLRQ' then n=n+1 end end;return n
end
P.before=function(p,q,code)
 if clicked or p~=A or q~=B or code~='WLRB' then return end
 -- Only the final chunk completes the transfer and reaches catalog admission.
 local index,total=p.H.sent[p.cursor].text:gsub('||','|'):match('|(%d+)/(%d+)|')
 if index~=total then return end
 -- The user clicks Sync Now on the receiver just before the full record completes.
 clicked=true;requestsBefore=Requests();heldBefore=Stats().admissionHeld or 0
 B.T.Until(B.H,function()return P.Ready(B)end)
 sentAtClick=#B.H.sent
 B.e.SlashCmdList.NEXUS('sync')
 callsAtArrival=full.calls
end
local id=P.Post(A,'NEXUS-TEST-REQUEST-FULL-RECORD')
heldId=id
P.Until(function()return clicked end)
assert((Stats().admissionHeld or 0)==heldBefore+1,'the arriving full record was held for the unsent request')
assert(full.calls==callsAtArrival and B.e.Nexus.Sync.WorkState().deferredAdmissions>=1,'it was retained without asking the catalog')
assert(P.Full(B,id)==nil,'a held record is not a stored record')
P.Until(function()return RequestSentSince(sentAtClick) end)
assert(not submittedBeforeRequest,'the request was transmitted before the held record was submitted')
P.Until(function()return Requests()>requestsBefore end)
P.Until(function()return P.Full(B,id)~=nil end)
local row,source=P.Full(B,id),A.e.Nexus.BuildCatalog.Get(id)
assert(#row.echoes==1 and row.echoes[1].spellId==200001 and row.echoes[1].quality==1 and row.echoes[1].stacks==3,'the exact three-copy record settles afterwards')
assert(row.ownerKey==source.ownerKey and row.lastModified==source.lastModified and row.title==source.title,'owner, revision and title match the source')
assert(full.accepted==1 and Stats().admissionResolved>=1,'one submission, by the ordinary deferred pump')
assert(Stats().storageRejected==0 and Stats().malformedRejected==0,'a held record is never refused or reclassified')
assert(#A.H.actions==0 and #B.H.actions==0,'zero gameplay mutation')
print('PASS full record held for an unsent manual request, request transmitted first, exact record settled once')
