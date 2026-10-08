-- Build-hash digest work on a collision-heavy catalog near the supported
-- capacity: builds and removal markers whose IDs all share one hash bucket
-- (markers count like builds), with numeric and string typed IDs. Every
-- pump's digest work is counted and never exceeds the fixed budget, whatever
-- the bucket holds; the digest equals the canonical bytes of the material
-- (sorted entry strings, djb2), a removal that the owner proves changes it
-- and one a stranger claims does not; the per-pump CPU time is reported
-- (os.clock, coarse) and loosely bounded. Real TOC boot, real catalog
-- admission, real revision bus; synthetic rows.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local BUILDS,MARKERS,NUMERIC=1800,1200,8  -- the catalog admits at most 2048 builds and 2048 markers
-- The cache's bucket function (djb2 over the ID text, eight buckets),
-- replicated to choose colliding IDs before the cache exists; the cache's
-- own function is checked against it after boot.
local function BucketOf(id)
 local text,hash=tostring(id),5381
 for i=1,#text do hash=((hash*33)+text:byte(i))%2147483648 end
 return (hash%8)+1
end
local TARGET=1
local function Colliding(prefix,count)
 local ids,n={},0
 while #ids<count do n=n+1;local id=prefix..n;if BucketOf(id)==TARGET then ids[#ids+1]=id end end
 return ids
end
local function Record(id,i)
 local name='Peer'..(i%50)
 return {id=id,title='Collide '..tostring(id),author=name,ownerKey=name:lower()..'@realm',realm='realm',ownerVerified=true,
  class='MAGE',postedAt=1,lastModified=1+(i%7),ordinaryComplete=true,loadoutAvailable=true,
  echoes={{spellId=200001+(i%40),quality=1,stacks=1+(i%3)},{spellId=200050+(i%30),quality=2,stacks=1}},
  lockedEchoes={},lockedComplete=true}
end
local buildIds,markerIds=Colliding('col-',BUILDS),Colliding('gone-',MARKERS)
local numericIds,k={},0
while #numericIds<NUMERIC do k=k+1;if BucketOf(k)==TARGET then numericIds[#numericIds+1]=k end end
local db=F.Database({version=2});db.communityBuilds={};db.syncTombstones={}
for i,id in ipairs(buildIds) do db.communityBuilds[id]=Record(id,i) end
for i,id in ipairs(numericIds) do
 db.communityBuilds[id]=Record(id,100+i)              -- number-typed identity
 db.communityBuilds[tostring(id)]=Record(tostring(id),200+i) -- its string twin, the same bucket
end
for i,id in ipairs(markerIds) do db.syncTombstones[id]={stamp=1+(i%5),author='Peer'..(i%50)} end
local H=F.Boot(db)
local C,Cache,Rev=Nexus.BuildCatalog,Nexus.BuildHashCache,Nexus.Revisions
local EVENT=Rev.BUILD_LIBRARY_CHANGED
local function Frames(predicate,limit)
 local n=0
 for _=1,limit or 20000 do H.Advance(.05,.05);n=n+1;if predicate() then return n end end
 error('bounded wait did not reach its condition after '..n..' frames')
end
local function Ready() return Cache.Stats().phase=='ready' end
Frames(Ready)
for _,id in ipairs({buildIds[1],buildIds[#buildIds],markerIds[1],numericIds[1],tostring(numericIds[1])}) do
 check(Cache.Bucket(id)==TARGET and Cache.Bucket(id)==BucketOf(id),'fixture: the cache buckets '..tostring(id)..' where this test expects')
end
local status=C.Status()
check(status.availableCount==BUILDS+2*NUMERIC,'fixture: every build is admitted: '..status.availableCount)
check(status.tombstoneCount==MARKERS,'fixture: every removal marker is admitted: '..status.tombstoneCount)
check(C.Get(numericIds[1])~=nil and C.Get(tostring(numericIds[1]))~=nil
 and type(C.Get(numericIds[1]).id)=='number' and type(C.Get(tostring(numericIds[1])).id)=='string',
 'fixture: a number-typed identity and its string twin are two rows')
check(status.buildIdentityLimit==2048 and status.tombstoneLimit==2048,'fixture: the catalog limits are 2048 builds and 2048 markers')

-- The canonical material, read from the catalog through the cache's own
-- entry builders (tests/prototype/typed_hash.lua pins those builders against
-- the compatibility fallback and the typed-ID material), hashed by the
-- reference definition. Entries are kept by ID for the material checks.
local function find(f,needle,seen)
 if type(f)~='function' or seen[f] then return end;seen[f]=true
 for i=1,100 do local n,v=debug.getupvalue(f,i);if not n then break end
  if n==needle then return v end
  if n~='_ENV' and type(v)=='function' then local got=find(v,needle,seen);if got then return got end end
 end
end
local BuildEntry=assert(find(Cache.Pump,'BuildEntry',{}),'cache BuildEntry')
local TombstoneEntry=assert(find(Cache.Pump,'TombstoneEntry',{}),'cache TombstoneEntry')
local material={}
local function Reference(mode)
 local buckets,bytes,entries={},0,0;for b=1,8 do buckets[b]={} end
 local token=assert(C.BeginSummaryCursor(),'reference summary cursor')
 for _=1,100000 do
  local summary,done,err=C.SummaryCursorNext(token)
  assert(not err,tostring(err))
  if type(summary)=='table' and (mode=='legacy' or summary.syncDelta) then
   local entry=BuildEntry(summary.id,summary);material[summary.id]=entry
   local bucket=buckets[Cache.Bucket(summary.id)];bucket[#bucket+1]=entry
  end
  if done then break end
 end
 local cursor
 for _=1,100000 do
  local id,tomb,done=C.TombstoneNext(cursor)
  if done or id==nil then break end
  local entry=TombstoneEntry(id,tomb);material['!'..tostring(id)]=entry
  local bucket=buckets[Cache.Bucket(id)];bucket[#bucket+1]=entry;cursor=id
 end
 local out={}
 for b=1,8 do
  table.sort(buckets[b]);local v=5381
  for _,s in ipairs(buckets[b]) do entries=entries+1;bytes=bytes+#s;for i=1,#s do v=((v*33)+s:byte(i))%2147483648 end end
  out[b]=#buckets[b]>0 and string.format('%x',v) or '0'
 end
 return table.concat(out,','),entries,bytes
end
local function Exact(label)
 local delta,deltaEntries,deltaBytes=Reference('delta')
 local legacy,legacyEntries,legacyBytes=Reference('legacy')
 check(Cache.Delta()==delta,label..': the delta digest is the canonical bytes')
 check(Cache.Legacy()==legacy,label..': the legacy digest is the canonical bytes')
 return deltaEntries+legacyEntries,deltaBytes+legacyBytes
end
local entries,bytes=Exact('start-up')
check(entries>=2*(BUILDS+MARKERS),'fixture: the material holds every build and marker in both modes: '..entries)
check(Cache.Delta():find('[1-9a-f]')~=nil and Cache.Legacy():find('[1-9a-f]')~=nil,'fixture: both digests carry real hashes')
local eligible=0
do local token=assert(C.BeginSummaryCursor());for _=1,100000 do local s,done=C.SummaryCursorNext(token);if type(s)=='table' and s.syncDelta then eligible=eligible+1 end;if done then break end end end
check(eligible==BUILDS+2*NUMERIC,'fixture: every build is a verified-owner delta row: '..eligible)

-- Explicit material expectations: the typed ID, the stamp, the completeness
-- flag and the fingerprint; a marker's stamp and author.
local seven=numericIds[1]
check(material[seven]:sub(1,#('number:'..seven..':'))=='number:'..seven..':' and material[tostring(seven)]:sub(1,#('string:'..seven..':'))=='string:'..seven..':',
 'a number-typed identity and its string twin are distinct material: '..material[seven]..' / '..material[tostring(seven)])
local row=C.Get(buildIds[1])
check(material[buildIds[1]]=='string:'..buildIds[1]..':'..tostring(row.lastModified)..':F:'..tostring(row.fingerprintHash),
 'a build entry is typed id, stamp, F and the fingerprint: '..material[buildIds[1]])
check(material['!'..markerIds[1]]=='!string:'..markerIds[1]..':'..db.syncTombstones[markerIds[1]].stamp..':'..db.syncTombstones[markerIds[1]].author,
 'a marker entry is !, typed id, stamp and author: '..material['!'..markerIds[1]])

-- Every pump: the digest work of that pump, read right after it, never
-- exceeds the fixed budget; the CPU time of each pump is sampled.
local budget=Cache.Stats().hashWorkBudget
check(budget==2048,'the digest work budget is the stated 2048 units per pump: '..tostring(budget))
local pumps,over,largest,clocks=0,0,0,{}
local real=Cache.Pump
Cache.Pump=function(...)
 local t=os.clock();local a,b=real(...);local dt=os.clock()-t
 local s=Cache.Stats()
 pumps=pumps+1
 if s.lastPumpWork>budget then over=over+1 end
 if s.lastPumpWork>largest then largest=s.lastPumpWork end
 clocks[#clocks+1]=dt
 return a,b
end
local function Distribution()
 table.sort(clocks)
 local function at(p) return clocks[math.max(1,math.floor(#clocks*p+0.5))]*1000 end
 return string.format('pumps=%d p50=%.2fms p90=%.2fms max=%.2fms',#clocks,at(0.5),at(0.9),clocks[#clocks]*1000)
end

-- 1. A cold warm-up of the whole collision bucket: bounded every pump, the
-- work counted by kind, the digest exact.
local before=Cache.Stats()
Rev.Advance(EVENT,{scope='all',reason='test collision cold'})
local frames=Frames(Ready)
local after=Cache.Stats()
check(over==0,'no pump exceeded the digest work budget: '..over..' of '..pumps..' pumps, largest '..largest)
check(largest==budget,'the busiest pump used exactly the budget: '..largest)
check(after.maxHashWorkPerPump<=budget and after.maxCollectedPerPump<=budget and after.maxComparesPerPump<=budget
 and after.maxMovesPerPump<=budget and after.maxBytesPerPump<=budget,'the reported per-pump maxima are within the budget')
local collected=after.hashCollected-before.hashCollected
local moves,compares,hashed=after.hashMoves-before.hashMoves,after.hashCompares-before.hashCompares,after.hashBytes-before.hashBytes
check(collected==entries,'every entry was collected once per mode: '..collected..' of '..entries)
check(hashed==bytes,'every byte of the material was hashed once: '..hashed..' of '..bytes)
check(moves>=collected and compares<=moves and compares>0,'the sort moved every entry at least once and compared fewer times than it moved: '..compares..' compares, '..moves..' moves')
check(after.sortPasses>before.sortPasses,'the sort ran in passes: '..(after.sortPasses-before.sortPasses))
check(after.fullRebuilds==before.fullRebuilds+1 and after.warmRestarts==before.warmRestarts,'one complete rebuild, no restart')
check(after.lastPumpWork<=budget,'the last pump is within the budget too')
local totalUnits=collected+moves+compares+hashed
check(frames>=math.floor(totalUnits/budget),'the warm-up took at least the pumps its units need: '..frames..' frames for '..totalUnits..' units')
print('COLLISION_COLD frames='..frames..' units='..totalUnits..' collected='..collected..' compares='..compares..' moves='..moves..' bytes='..hashed..' '..Distribution())
check(clocks[#clocks]<0.25,'no pump took a quarter second of CPU (coarse os.clock): '..string.format('%.1f ms',clocks[#clocks]*1000))
Exact('after the cold warm-up')

-- 2. Markers decide BucketHasTombstone: the collision bucket has them, a
-- bucket with no marker has none.
check(Cache.BucketHasTombstone(TARGET)==true,'the collision bucket reports its markers')
check(Cache.BucketHasTombstone(TARGET%8+1)==false,'a bucket without markers reports none')

-- 3. Authority: a removal claimed by a stranger changes nothing; the same
-- removal proved by the owner is admitted, re-hashes only that bucket, and
-- the digest follows the canonical bytes.
local victim=buildIds[2]
local owner=C.Get(victim)
local deltaBefore,legacyBefore=Cache.Delta(),Cache.Legacy()
local refused,why=C.SetTombstone(victim,{stamp=9,author=owner.author},{source='remote',sender='Nobody-realm'})
check(refused==false,'a stranger cannot remove the build: '..tostring(why))
Frames(Ready,200)
check(Cache.Delta()==deltaBefore and Cache.Legacy()==legacyBefore,'a refused removal leaves both digests unchanged')
clocks,over,largest={},0,0
before=Cache.Stats()
local removed,removeWhy,ticket=C.SetTombstone(victim,{stamp=9,author=owner.author},{source='remote',sender=owner.author..'-realm'})
if removed==nil and type(ticket)=='table' then Frames(function() return ticket.state~='pending' end) end
check(C.TombstoneState(victim).state~='NONE','the owner-proved removal is admitted: '..tostring(removeWhy))
Frames(Ready)
after=Cache.Stats()
check(over==0,'no pump of the targeted re-hash exceeded the budget: '..over)
check(after.targetedInvalidations>before.targetedInvalidations and after.fullInvalidations==before.fullInvalidations,'the removal was a targeted update, not a rebuild')
check(Cache.Delta()~=deltaBefore and Cache.Legacy()~=legacyBefore,'an admitted removal changes both digests')
Exact('after an owner-proved removal')

-- 4. A burst of colliding admissions once ready: each a targeted update,
-- every pump bounded, the digest exact after each.
for i=1,3 do
 clocks,over,largest={},0,0
 local id=Colliding('late-'..i..'-',1)[1]
 local ok,putWhy,putTicket=C.Put(Record(id,900+i),{source='sync'})
 if ok==nil and type(putTicket)=='table' then Frames(function() return putTicket.state~='pending' end) end
 check(C.Get(id)~=nil,'fixture: the colliding build '..id..' is admitted: '..tostring(putWhy))
 Frames(Ready)
 check(over==0,'no pump exceeded the budget after admission '..i)
 Exact('after colliding admission '..i)
end
print('COLLISION_BURST '..Distribution())
Cache.Pump=real
print('PASS hash_cache_collision_budget builds='..BUILDS..' markers='..MARKERS..' checks='..checks)
