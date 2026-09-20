-- A real owner Share of 79 exact entries is a multi-chunk transfer. Deferred
-- inbound admission on the SENDER must not put a catalog transaction between
-- its chunks, and must not keep the response from being prepared at all.
-- Fixture after the independent review's multichunk_pressure probes. The same
-- pressure completes on b49afd2, which refuses the inbound items instead.
local P=dofile('tests/prototype/sync_pair_support.lua')
local function Run(stage)
 local A,B=P.Boot({'ChunkAlpha','ChunkBeta'},20)
 local echoes={};for j=1,79 do echoes[j]={spellId=200000+j,quality=j%4,stacks=1}end
 A.H.perks.serverBuildSlots[102].echoes=echoes
 local chunks,pressed={},false
 local function Stats()return A.e.Nexus.Sync.Stats()end
 -- The admission counter is read inside the sender's real send calls. Sync
 -- transmits first and runs deferred admission afterwards in the same turn, so
 -- a value read after that turn would charge the last chunk with the admission
 -- that correctly follows a completed transfer. Observe only; calls pass through.
 local atTransmission={}
 for _,name in ipairs({'SendChatMessage','SendAddonMessage'})do
  local real=A.e[name]
  A.e[name]=function(...)atTransmission[#A.H.sent+1]=Stats().admissionResolved;return real(...)end
 end
 P.before=function(p,q,code)
  if p~=A then return end
  if code=='WLRB' then
   local text=p.H.sent[p.cursor].text:gsub('||','|'):gsub('^P%d+:','')
   local id,index,total=text:match('^WLRB|[^|]+|([^|]+)|[^|]+|(%d+)/(%d+)|')
   chunks[#chunks+1]={time=p.H.now,id=id,index=tonumber(index),total=tonumber(total),
    resolved=assert(atTransmission[p.cursor],'every transmitted chunk was observed at its send call')}
  end
  -- Sixteen valid summaries from verified owners plus one that takes the
  -- ticket, through the real receive callback, at the chosen stage.
  if pressed or code~=(stage=='summary' and 'WLBI' or 'WLRB') then return end
  pressed=true
  assert(P.Ready(A),'fixture: pressure begins on a ready sender')
  for i=1,17 do
   local owner='ChunkPressure'..((i-1)%4+1)
   local d={id='chunk-pressure-'..i,t='Synthetic chunk pressure '..i,a=owner..'-Ebonhold',
    o=A.e.Nexus.Identity.OwnerKey(owner,'Ebonhold'),c='MAGE',m=A.e.time()+i,h='a1',n=3}
   P.Channel(A,'WLBI|'..d.a..'|'..A.e.Nexus.Codec.Base64Encode(A.e.Nexus.Codec.JSONEncode(d)),d.a)
  end
  assert(A.e.Nexus.Sync.WorkState().deferredAdmissions==16,'fixture: sixteen deferred items behind one accepted holder')
 end
 local id=P.Post(A,'NEXUS-TEST-MULTICHUNK-'..stage)
 -- The wait may end without completion. The no-interleaving check below
 -- runs first in either case, so a product that interleaves is reported as
 -- interleaving, not only as a transfer that never finished.
 local completed=pcall(P.Until,function()return P.Full(B,id)~=nil end,9000)
 assert(pressed,'fixture: pressure was applied at the '..stage..' stage')
 local source=assert(A.e.Nexus.BuildCatalog.Get(id));assert(#source.echoes==79,'real owner Share saved the exact 79-entry record')
 -- Every attempt is one contiguous run of chunk 1..n with one total. A retry
 -- is a separate attempt and is never mixed with the one before it. In every
 -- complete attempt, no deferred admission was started between its chunks,
 -- and ordinary send pacing is unchanged.
 local attempts,current={},nil
 for _,c in ipairs(chunks)do
  if c.id==id then
   if c.index==1 then current={total=c.total};attempts[#attempts+1]=current
   else assert(current and c.total==current.total and c.index==#current+1,'chunks of one attempt are contiguous: '..c.index..'/'..c.total)end
   current[#current+1]=c
  end
 end
 local complete,first=0,nil
 for _,attempt in ipairs(attempts)do
  assert(attempt.total>1,'the transfer really uses several chunks: '..attempt.total)
  for i=2,#attempt do
   assert(attempt[i].resolved==attempt[i-1].resolved,'a started transfer is not interleaved with deferred admissions: chunk '..attempt[i].index..'/'..attempt.total..' followed '..(attempt[i].resolved-attempt[i-1].resolved)..' admission(s)')
   assert(attempt[i].time-attempt[i-1].time>=1.1-1e-6,'ordinary send pacing is unchanged')
  end
  if #attempt==attempt.total then complete=complete+1;first=first or attempt end
 end
 assert(completed,'the exact record completes under deferred pressure without any extended deadline')
 local row=P.Full(B,id)
 assert(row.ownerKey==source.ownerKey and row.lastModified==source.lastModified and B.T.Equal(row.echoes,source.echoes),'receiver committed the exact record: every ID, quality and copy')
 assert(complete>=1,'at least one attempt transmitted every chunk')
 local total,resolvedDuring=first.total,first[#first].resolved-first[1].resolved
 assert(resolvedDuring==0,'no deferred admission inside the first complete attempt')
 assert(Stats().expiredDropped==nil or Stats().expiredDropped==0,'no outbound chunk expired')
 -- Deferred inbound work is not abandoned: it proceeds after the transfer.
 local resolvedAtComplete=Stats().admissionResolved
 P.Until(function()return Stats().admissionResolved>resolvedAtComplete or A.e.Nexus.Sync.WorkState().deferredAdmissions==0 end,9000)
 assert(Stats().admissionResolved>resolvedAtComplete,'deferred items are admitted after the transfer completes')
 assert(Stats().malformedRejected==0 and #A.H.actions==0 and #B.H.actions==0,'valid items stay valid; zero gameplay mutation')
 print(string.format('PASS %s-stage pressure: %d-chunk transfer complete in %.1fs, %d admission(s) between its chunks, deferred work continues',
  stage,total,first[#first].time-first[1].time,resolvedDuring))
end
Run('chunk')
Run('summary')
