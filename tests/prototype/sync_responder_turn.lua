-- An ordinary Sync Now must obtain the owner's exact record from a responder
-- that keeps receiving valid inbound records. Unheld, every ready moment of
-- the responder's catalog goes to the next inbound record, the lifecycle
-- withholds every full Sync turn, and the pending response expires with zero
-- serialization although the request was sent.
local S=dofile('tests/prototype/sync_responder_support.lua')
local P=S.P

-- Quiet control.
local run=S.Scenario({label='quiet',names={'TurnAlpha','TurnBeta'},rows=5})
S.Served(run);S.Exact(run,'control: the ordinary request delivers the record')
local complete=S.Attempts(run);assert(complete>=1,'control: one complete attempt')
print(string.format('PASS quiet control: exact 79-entry record in %.1fs',run.seconds))

-- Pressured: one valid summary at every ready frame of the responder.
run=S.Scenario({label='pressured',names={'TurnGamma','TurnDelta'},rows=5,traffic={'A'}})
S.Served(run)
S.Exact(run,'an ordinary request is answered by a responder that keeps receiving valid inbound records')
complete=S.Attempts(run);assert(complete>=1,'at least one attempt transmitted every chunk')
local a=run.Stats(run.A)
assert((a.admissionHeld or 0)>=1 and run.arrivals.A>=(a.admissionHeld or 0),'fixture: valid inbound records were retained while the response was owed')
assert(a.malformedRejected==0,'valid items stay valid')
assert(a.storageRejected==(a.admissionOverflow or 0)+(a.admissionExpired or 0)+(a.admissionCancelled or 0),'a retained item is refused only by the existing bounds, its own deadline or cancellation')
assert(run.A.e.Nexus.Sync.WorkState().deferredAdmissions<=64,'the existing total bound holds')
-- Retained inbound work resumes after the transfer while the same traffic
-- continues at every ready frame: a newer arrival never overtakes it.
local resolved=a.admissionResolved or 0
P.Until(function()return (run.Stats(run.A).admissionResolved or 0)>=resolved+3 end,4000)
local stored=0;for i=1,run.arrivals.A do if run.A.e.Nexus.BuildCatalog.Get('turn-pressured-A-'..i) then stored=stored+1 end end
assert(stored>=3,'retained items reached the catalog')
print(string.format('PASS pressured responder: exact record in %.1fs, %d of %d inbound items retained, retained work resumed under the same traffic (%d stored)',
 run.seconds,a.admissionHeld,run.arrivals.A,stored))

-- Separate control, not a substitute for the case above: the traffic pauses
-- and the retained queue drains completely, with nothing left to expire.
run.trafficOn=false
P.Until(function()return run.A.e.Nexus.Sync.WorkState().deferredAdmissions==0 end,12000)
local z=run.Stats(run.A)
assert((z.admissionExpired or 0)==(a.admissionExpired or 0),'paused-traffic control: no retained item expired while the queue drained')
print(string.format('PASS paused-traffic drain control: queue empty after %d admissions',(z.admissionResolved or 0)-resolved))