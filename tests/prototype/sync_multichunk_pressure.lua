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
 P.before=function(p,q,code)
  if p~=A then return end
  if code=='WLRB' then
   local text=p.H.sent[p.cursor].text:gsub('||','|'):gsub('^P%d+:','')
   local id,index,total=text:match('^WLRB|[^|]+|([^|]+)|[^|]+|(%d+)/(%d+)|')
   chunks[#chunks+1]={time=p.H.now,id=id,index=tonumber(index),total=tonumber(total),resolved=Stats().admissionResolved}
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
 local source
 P.Until(function()
  source=source or A.e.Nexus.BuildCatalog.Get(id)
  return P.Full(B,id)~=nil
 end,9000)
 assert(pressed,'fixture: pressure was applied at the '..stage..' stage')
 source=assert(A.e.Nexus.BuildCatalog.Get(id));assert(#source.echoes==79,'real owner Share saved the exact 79-entry record')
 local row=P.Full(B,id)
 assert(row.ownerKey==source.ownerKey and row.lastModified==source.lastModified and B.T.Equal(row.echoes,source.echoes),'receiver committed the exact record: every ID, quality and copy')
 -- The first complete transfer of this ID: no catalog transaction was started
 -- between its chunks, and ordinary send pacing is unchanged.
 local first,total={},chunks[1].total
 assert(total>1,'the transfer really uses several chunks: '..total)
 for _,c in ipairs(chunks)do if c.id==id and #first<total and c.index==#first+1 then first[#first+1]=c end end
 assert(#first==total,'every chunk of one transfer was transmitted: '..#first..'/'..total)
 local interrupted=0
 for i=2,#first do
  if first[i].resolved~=first[i-1].resolved then interrupted=interrupted+1 end
  assert(first[i].time-first[i-1].time>=1.1-1e-6,'ordinary send pacing is unchanged')
 end
 local resolvedDuring=first[#first].resolved-first[1].resolved
 assert(interrupted==0 and resolvedDuring==0,'a started transfer is not interleaved with deferred admissions: '..resolvedDuring..' admitted between its chunks')
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
