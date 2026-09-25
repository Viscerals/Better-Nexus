-- Internal retention maintenance: the busy retry is bounded.
-- A retention run that finds the catalog busy is scheduled again. The limit
-- counts retries after the first busy run of a chain, so one chain makes at
-- most 1 + 64 = 65 runs. The delays grow 5, 10, 20 and 40 s, then stay at
-- 60 s (64 delays, 3675 s in total). After the last busy run nothing more is
-- scheduled. Retention.Request during the chain joins it, so only one chain
-- exists. The start-up run (Retention.Init) is a separate call and is not
-- retried. A busy run opens no maintenance handle and changes no catalog
-- state, and a request after the busy period still runs.
-- Real TOC boot, real scheduler and retention owner; synthetic data; the
-- harness clock advances in fixed 0.5 s steps (deterministic).
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local clock=1790000000
local BUSY=5000
local db={settingsVersion=5,settings={},chars={},communityBuilds={},
 communityRetentionEvictions={['legacy-1']=1700000000,['legacy-2']=1700000001}}
local Hh,start
local runs={}
F.fileHooks={[ [[core\DataRetention.lua]] ]=function()
 local C=Nexus.BuildCatalog;local begin=C.BeginCatalogMaintenance
 C.BeginCatalogMaintenance=function(request)
  if type(request)=='table' and request.operation=='retention' and Hh and start and Hh.now<start+BUSY then
   runs[#runs+1]={t=Hh.now-start}
   return nil,'ROOT_MUTATION_PENDING'
  end
  return begin(request)
 end
 local R=Nexus.DataRetention;local enforce=R.Enforce
 R.Enforce=function(database,reason)
  local before=#runs
  local result=enforce(database,reason)
  if #runs>before then runs[#runs].reason=reason;runs[#runs].result=result end
  return result
 end
end}
local H=F.Boot(db,function(h) Hh=h;start=h.now;time=function() return clock+math.floor(h.now) end end)
F.fileHooks=nil
local C,R,S=Nexus.BuildCatalog,Nexus.DataRetention,Nexus.Scheduler
-- Read after the start-up publication (about 1.6 s) and before the chain's
-- first retry.
local generation
local joined
for _=1,math.floor(4500/0.5) do
 H.Advance(.5,.5)
 if generation==nil and Hh.now-start>=3 then generation=C.Status().generation end
 if joined==nil and Hh.now-start>=600 then joined=R.Request('test: request during the chain') end
end
local chain,startup,other={},0,0
for _,run in ipairs(runs)do
 if run.reason=='shared catalog ready' then chain[#chain+1]=run
 elseif run.reason=='startup' then startup=startup+1
 else other=other+1 end
 check(type(run.result)=='table' and run.result.blocked==true and run.result.reason=='ROOT_MUTATION_PENDING',
  'every busy run ends blocked and busy: '..tostring(run.reason))
end
check(startup==1,'the start-up run is one separate call and is not retried: '..startup)
check(#chain==65,'one chain makes the first busy run plus 64 retries: '..#chain..' runs')
check(other==0 and joined==true,'a request during the chain joins it; no second chain starts')
check(#runs==66,'the start-up run and the chain are all the busy runs: '..#runs)
local expected={5,10,20,40}
for i=5,64 do expected[i]=60 end
for i=1,64 do
 local gap=chain[i+1].t-chain[i].t
 check(gap>=expected[i]-0.001 and gap<=expected[i]+1,
  string.format('retry %d waits %d s: %.2f s',i,expected[i],gap))
end
local span=chain[65].t-chain[1].t
check(span>=3675-0.001 and span<=3675+64,string.format('the measured chain lasts 3675 s from its first to its last run: %.1f s',span))
local now=Hh.now-start
check(not S.Pending('data-retention.enforce'),'after the last retry nothing is scheduled')
check(now-chain[65].t>=600,string.format('no run for %.0f s after the last retry',now-chain[65].t))
check(C.Status().generation==generation and C.ManualPreparationStatus().ready,
 'the busy runs changed no catalog state and hold no catalog work')
local meta=(NexusDB.authorityBundle or {}).dataRetention or {}
check(meta.markerFirstSeen==nil,'nothing was recorded while the catalog stayed busy')
-- The chain that stopped at its limit leaves one bounded support record.
local deferred={}
for _,incident in ipairs(Nexus.SupportIncidents.History())do
 if incident.kind=='retention-deferred' then deferred[#deferred+1]=incident end
end
check(#deferred==1 and deferred[1].reason=='ROOT_MUTATION_PENDING' and deferred[1].committed==false
 and deferred[1].occurrences==1,'the stopped chain leaves one retention-deferred record (busy, not committed, once)')
-- After the busy period a new request runs and records the first observations.
for _=1,math.floor((BUSY-now+10)/0.5) do H.Advance(.5,.5) end
check(R.Request('test: after the busy period')==true,'a request after the busy period is scheduled')
for _=1,40 do H.Advance(.5,.5) end
local seen=((NexusDB.authorityBundle or {}).dataRetention or {}).markerFirstSeen or {}
local count=0;for _ in pairs(seen)do count=count+1 end
check(count==2,'the later run records both first observations: '..count)
print('PASS retention_busy_retry_bound: start-up run once, one chain of 1 + 64 busy runs, delays 5/10/20/40 then 60 s (3675 s), terminal stop with one deferred record, request joins the chain, no catalog change, later request runs checks='..checks)
