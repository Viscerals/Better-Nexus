-- A catalog transaction already in flight on the responder when the ordinary
-- request arrives is never cut short, and no lifetime is extended for it.
--  * Shorter than the response lifetime: the request waits for it, the next
--    inbound records are retained, and the response is served.
--  * Longer than PENDING_TTL: the pending response still expires unserved at
--    its unchanged lifetime. This is a disclosed limit, asserted as such.
local S=dofile('tests/prototype/sync_responder_support.lua')
local P=S.P

local run=S.Scenario({label='fshort',names={'FlightAlpha','FlightBeta'},rows=5,traffic={'A'},inflight=true})
assert(run.readyAtRequest==false,'fixture: the request arrived while the responder catalog was busy')
S.Served(run);S.Exact(run,'a request that arrives during a short transaction is served after it')
assert(S.Attempts(run)>=1,'one complete attempt')
print(string.format('PASS short in-flight transaction: first serialization +%.1fs, exact record in %.1fs',run.seen.serialization-run.requestAt,run.seconds))

-- The transaction must outlast the 30-second response lifetime. The shared
-- timed drive would finish this root sooner, so this scenario runs at the
-- supported no-clock pacing (one slice per update) and is given the longer
-- observation budget that pacing needs.
local PACING=dofile('tests/prototype/startup_support.lua')
local restorePacing=PACING.SingleSlicePacing()
run=S.Scenario({label='flong',names={'FlightGamma','FlightDelta'},rows=100,traffic={'A'},inflight=true,limit=12000,stop=function(r)return r.firstClaimId~=nil end})
restorePacing()
assert(run.done and run.readyAtRequest==false,'fixture: the request arrived while the responder catalog was busy')
local A=run.A
local waited=run.firstClaimAt-run.requestAt
assert(waited>30,'fixture: the transaction in flight outlasted the unchanged 30-second response lifetime: '..waited)
assert(run.claimAt==nil and run.firstClaimId~=run.requestId and run.requests>=2,'the original request was never claimed or served; the first claim belongs to a later request of the same requester: '..tostring(run.firstClaimId))
assert(#run.chunks==0 and run.Stats(run.B).useful~=true,'nothing is reported as delivered for the original request')
assert(run.Stats(A).malformedRejected==0 and #A.H.actions==0 and #run.B.H.actions==0,'valid items stay valid; zero gameplay mutation')
print(string.format('LIMIT long in-flight transaction: original request %s was never served; the first responder claim came +%.1fs later for request %s (request %d of the requester); no lifetime was extended',
 run.requestId,waited,run.firstClaimId,run.requests))
