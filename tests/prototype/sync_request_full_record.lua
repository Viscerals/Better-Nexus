-- The manual-request hold covers the full-record consumer too. A real full
-- record arrives at a receiver whose explicit Sync Now is accepted and unsent:
-- it is retained by the scoped deferred owner, the request is transmitted
-- first, and the exact record then settles through the ordinary pump.
local P=dofile('tests/prototype/sync_pair_support.lua')
local A,B=P.Boot({'ReadyAlpha','ReadyBeta'},5)
local C=B.e.Nexus.BuildCatalog
local function Stats()return B.e.Nexus.Sync.Stats()end
local full={calls=0,accepted=0}
local put=C.Put
C.Put=function(row,options,...)   -- observe only
 local ok,why,ticket=put(row,options,...)
 if type(row.echoes)=='table' and #row.echoes>0 then
  full.calls=full.calls+1
  if ok==true or (ok==nil and type(ticket)=='table')then full.accepted=full.accepted+1 end
 end
 return ok,why,ticket
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
 B.e.SlashCmdList.NEXUS('sync')
 callsAtArrival=full.calls
end
local id=P.Post(A,'NEXUS-TEST-REQUEST-FULL-RECORD')
P.Until(function()return clicked end)
assert((Stats().admissionHeld or 0)==heldBefore+1,'the arriving full record was held for the unsent request')
assert(full.calls==callsAtArrival and B.e.Nexus.Sync.WorkState().deferredAdmissions>=1,'it was retained without asking the catalog')
assert(P.Full(B,id)==nil,'a held record is not a stored record')
P.Until(function()return Requests()>requestsBefore end)
assert(full.accepted==0,'the request was transmitted before the held record was submitted')
P.Until(function()return P.Full(B,id)~=nil end)
local row,source=P.Full(B,id),A.e.Nexus.BuildCatalog.Get(id)
assert(#row.echoes==1 and row.echoes[1].spellId==200001 and row.echoes[1].quality==1 and row.echoes[1].stacks==3,'the exact three-copy record settles afterwards')
assert(row.ownerKey==source.ownerKey and row.lastModified==source.lastModified and row.title==source.title,'owner, revision and title match the source')
assert(full.accepted==1 and Stats().admissionResolved>=1,'one submission, by the ordinary deferred pump')
assert(Stats().storageRejected==0 and Stats().malformedRejected==0,'a held record is never refused or reclassified')
assert(#A.H.actions==0 and #B.H.actions==0,'zero gameplay mutation')
print('PASS full record held for an unsent manual request, request transmitted first, exact record settled once')
