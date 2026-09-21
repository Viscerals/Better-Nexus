-- Exact ordering on a responder that has been ready and idle for longer than
-- PENDING_TTL: a fresh ordinary WLRQ is delivered, then one valid summary
-- arrives before the responder's next frame. The service window belongs to
-- the owed work, not to catalog readiness: the summary is retained, the
-- response is served inside its unchanged lifetime, and the summary then
-- settles. Repeated arrivals and repeated requests never restart the bound.
local S=dofile('tests/prototype/sync_responder_support.lua')
local P=S.P
local heldAtArrival,readyAfter,itemId
-- First where the ordering decides the outcome: on a 100-row responder (the
-- requester keeps 5 rows; its own commit time is a separate matter) one
-- inbound summary is a catalog transaction of several minutes, far beyond the
-- response lifetime. Retained, it costs the fresh request nothing. The idle
-- period is long enough for the responder's own scheduled catalog maintenance
-- to finish first; that maintenance is a separate owner and a separate limit.
local run=S.Scenario({label='agedlarge',names={'AgedGamma','AgedDelta'},rows={100,5},idle=150,afterRequest=function(r)
 local before=r.Stats(r.A).admissionHeld or 0
 S.Summary(r.A,'aged-large',1)
 heldAtArrival=(r.Stats(r.A).admissionHeld or 0)-before
end})
S.Served(run);S.Exact(run,'the original request is served on a large responder although a valid summary followed it at once')
assert(heldAtArrival==1,'the summary was retained')
assert(S.Attempts(run)>=1,'one complete attempt')
print(string.format('PASS aged-ready ordering at 100 rows: first serialization +%.1fs, exact record in %.1fs',run.seen.serialization-run.requestAt,run.seconds))

-- The same ordering at 5 rows, with the mechanism and its bounds.
heldAtArrival=nil
run=S.Scenario({label='aged',names={'AgedAlpha','AgedBeta'},rows=5,idle=40,afterRequest=function(r)
 assert(P.Ready(r.A) and r.A.e.Nexus.Sync.WorkState().pendingResponses==1,'fixture: fresh pending response on a long-ready responder')
 local before=r.Stats(r.A).admissionHeld or 0
 itemId=S.Summary(r.A,'aged-item',1)
 heldAtArrival=(r.Stats(r.A).admissionHeld or 0)-before
 readyAfter=P.Ready(r.A)
end})
assert(heldAtArrival==1 and readyAfter,'the summary that follows a fresh request on a long-ready responder is retained; it does not take the catalog')
S.Served(run);S.Exact(run,'the fresh request is served after more than 30 seconds of idle readiness')
assert(S.Attempts(run)>=1 and #run.chunks==run.chunks[1].total,'one complete attempt, and only one')
-- Fixed bound for one started transfer: this single measured attempt, taken
-- now, before any later transfer exists.
local transfer=run.chunks[#run.chunks].time-run.chunks[1].time+1.1
local A=run.A
P.Until(function()return A.e.Nexus.BuildCatalog.Get(itemId)~=nil end,4000)
local a=run.Stats(A)
assert(a.storageRejected==0 and a.malformedRejected==0 and (a.admissionExpired or 0)==0,'the retained summary settled; nothing was refused or expired')
print(string.format('PASS aged-ready ordering: summary retained, first serialization +%.1fs, exact record, summary stored afterwards',run.seen.serialization-run.requestAt))

-- Sustained owed work: a new valid request from a different requester every
-- thirteen seconds, so that a response or its transfer is owed all the time.
-- One retained summary must still be admitted inside the fixed bound, and a
-- later arrival queues behind it instead of overtaking it. Neither the later
-- arrival nor the later requests restart the bound.
P.Until(function()return P.Ready(A) and A.e.Nexus.Sync.WorkState().deferredAdmissions==0 end,4000)
P.Advance(35)
local n,nextAt,first,firstAt,later,admittedAt,resolvedBefore=0,0,nil,nil,nil,nil,0
local function Request()
 n=n+1;local name='AgedRequester'..n
 local text=run.requestText:gsub('^WLRQ|[^|]+|','WLRQ|'..name..'|'):gsub('c1%-[%w%-]+','c1-'..(7000+n)..'-'..(1000+n))
 P.Channel(A,text,name..'-Ebonhold')
end
local scheduled=A.e.Nexus.Sync.ResponseStats()
for step=1,2400 do
 if A.H.now>=nextAt then Request();nextAt=A.H.now+13 end
 if not first and n>=1 then
  assert(A.e.Nexus.Sync.WorkState().pendingResponses>=1,'fixture: the synthetic valid request is pending on the responder')
  resolvedBefore=run.Stats(A).admissionResolved or 0
  first=S.Summary(A,'aged-sustained',1);firstAt=A.H.now
  assert(A.e.Nexus.Sync.WorkState().deferredAdmissions==1,'fixture: retained while work is owed')
 elseif first and not later and A.H.now-firstAt>5 then
  later=S.Summary(A,'aged-sustained',2)
 end
 P.Step()
 -- Admission (the pump submits the item) is distinct from catalog commit.
 if first and not admittedAt and (run.Stats(A).admissionResolved or 0)>resolvedBefore then admittedAt=A.H.now end
 if first and A.e.Nexus.BuildCatalog.Get(first) then break end
end
assert(admittedAt,'the retained summary was admitted by the pump')
local yielded,committed=admittedAt-firstAt,A.H.now-firstAt
assert(yielded<=30+transfer+.1,string.format('admitted within the unchanged 30-second yield cap plus one started transfer (%.1fs), although %d requests arrived meanwhile: %.1f',transfer,n,yielded))
assert(A.e.Nexus.BuildCatalog.Get(first),'the admitted summary then committed')
assert(later and A.e.Nexus.BuildCatalog.Get(later)==nil,'the later arrival kept its place behind the older one')
assert(n>=3 and A.e.Nexus.Sync.ResponseStats().entryPreparations>scheduled.entryPreparations,'fixture: requests kept arriving and the responder kept serving them')
print(string.format('PASS sustained owed work: retained summary admitted after %.1fs (fixed bound %.1fs), committed after %.1fs, %d requests arriving; FIFO order kept',yielded,30+transfer,committed,n))

-- A blocked wire owes nothing that can be sent: the item takes the catalog.
for _,blocker in ipairs({'combat','suspended'})do
 P.Until(function()return P.Ready(A) and A.e.Nexus.Sync.WorkState().deferredAdmissions==0 end,9000)
 if blocker=='combat' then A.H.combat=true else A.e.Nexus.SyncWire.suspended=true end
 Request()
 assert(A.e.Nexus.Sync.WorkState().pendingResponses>=1,'fixture: owed response while blocked')
 local held,sent=run.Stats(A).admissionHeld or 0,#A.H.sent
 local id=S.Summary(A,'aged-'..blocker,1)
 assert((run.Stats(A).admissionHeld or 0)==held and not P.Ready(A),'a blocked wire holds nothing; the valid item takes the catalog directly: '..blocker)
 A.T.Until(A.H,function()return A.e.Nexus.BuildCatalog.Get(id)~=nil end,8000)
 assert(#A.H.sent==sent,'nothing is transmitted while blocked')
 if blocker=='combat' then A.H.combat=false else A.e.Nexus.SyncWire.suspended=false end
end
assert(#A.H.actions==0 and #run.B.H.actions==0,'zero gameplay mutation')
print('PASS blocked wire: no retention for a transmission that cannot happen')
