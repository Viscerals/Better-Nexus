-- Full-record recovery (WLLQ) under interleaved traffic on BOTH peers. The
-- requester holds only the owner's summary, so its queued recovery request
-- must reach the wire, and the responder's pending loadout must be served,
-- while each peer keeps receiving valid inbound records. A queued recovery
-- request is sent only in a full Sync turn; unheld, every ready moment of the
-- requester's catalog goes to the next inbound record and the request never
-- leaves. Real lifecycle, recovery owner, transport, reconciler, admission and
-- catalog on two isolated runtimes; synthetic data only.
local S=dofile('tests/prototype/sync_responder_support.lua')
local P=S.P
local function Run(label,names,traffic)
 local A,B=P.Boot(names,5)
 local echoes={};for j=1,79 do echoes[j]={spellId=200000+j,quality=j%4,stacks=1}end
 A.H.perks.serverBuildSlots[102].echoes=echoes
 local arrivals,on,last={A=0,B=0},false,{}
 for name,p in pairs({A=A,B=B})do
  local active=false;for _,n in ipairs(traffic)do active=active or n==name end
  local advance=p.H.Advance
  p.H.Advance=function(...)
   local r=advance(...)
   -- One valid summary at the first ready frame, at most one per second:
   -- enough to take every ready moment of an unheld catalog, without
   -- exceeding what the catalog can commit by an order of magnitude.
   if active and on and P.Ready(p) and p.H.now-(last[name] or 0)>=1 then
    last[name]=p.H.now;arrivals[name]=arrivals[name]+1;S.Summary(p,label..'-'..name,arrivals[name])
   end
   return r
  end
 end
 -- Only the owner's summary reaches the requester. Its full-record chunks
 -- are sent by the real transport and not delivered, so the requester must
 -- recover the full record with its own request.
 local id,requestAt,chunks
 local deliver=B.H.Fire
 B.H.Fire=function(event,prefixOrText,text,...)
  local wire=event=='CHAT_MSG_ADDON' and text or prefixOrText
  if not requestAt and type(wire)=='string' and wire:gsub('||','|'):gsub('^P%d+:',''):find('^WLRB|') then return end
  return deliver(event,prefixOrText,text,...)
 end
 P.before=function(p,q,code)
  if p==A and code=='WLBI' then on=true end
  if p==B and code=='WLLQ' and not requestAt then requestAt=B.H.now;chunks=0 end
  if p==A and code=='WLRB' and requestAt then chunks=chunks+1 end
 end
 id=P.Post(A,'NEXUS-TEST-RECOVERY-'..label)
 local done=pcall(P.Until,function()return P.Full(B,id)~=nil end,4000)
 print(string.format('OBSERVED %s complete=%s recovery_request=%s chunks_after_request=%s requester_held=%s responder_held=%s arrivals=%d/%d',
  label,tostring(done),requestAt and 'sent' or 'never',tostring(chunks),tostring(B.e.Nexus.Sync.Stats().admissionHeld),
  tostring(A.e.Nexus.Sync.Stats().admissionHeld),arrivals.A,arrivals.B))
 assert(requestAt,'the requester transmitted its recovery request for the full record')
 assert(done,'the exact full record arrived through recovery')
 local row,source=P.Full(B,id),A.e.Nexus.BuildCatalog.Get(id)
 assert(row.ownerKey==source.ownerKey and row.lastModified==source.lastModified and row.title==source.title and row.isMine~=true,'owner, revision and title match the source')
 assert(#row.echoes==79 and B.T.Equal(row.echoes,source.echoes),'the requester committed the exact record: every ID, quality and copy')
 for _,p in ipairs({A,B})do assert(p.e.Nexus.Sync.Stats().malformedRejected==0 and #p.H.actions==0,'valid items stay valid; zero gameplay mutation')end
 return A,B,arrivals
end
Run('quiet',{'RecoverAlpha','RecoverBeta'},{})
print('PASS quiet control: summary only, recovery request sent, exact 79-entry record committed')
local A,B=Run('both',{'RecoverGamma','RecoverDelta'},{'A','B'})
assert((B.e.Nexus.Sync.Stats().admissionHeld or 0)>=1,'fixture: the requester retained inbound records while its recovery request was owed')
assert((A.e.Nexus.Sync.Stats().admissionHeld or 0)>=1,'fixture: the responder retained inbound records while the loadout was owed')
print('PASS interleaved traffic on both peers: recovery request sent, pending loadout served, exact record committed')