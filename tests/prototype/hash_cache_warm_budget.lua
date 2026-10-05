-- Build-hash warm-up: finite frames to readiness on a large catalog, bounded
-- work per pump, digest bytes exactly those of the canonical material, a
-- record-scope revision absorbed during the hashing phase instead of a full
-- restart, and fail-closed resets for every unknown change (all-scope or
-- id-less revision, catalog identity change). The Sync readiness gate is
-- unchanged: while the cache prepares, no digest is served. Real TOC boot,
-- real catalog, real revision bus; synthetic rows.
local F=dofile('tests/prototype/format5_support.lua')
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local N=320
local function Record(i)
 return {id='warm-'..i,title='Warm '..i,author='Peer'..(i%50)..'-Realm',ownerKey='peer'..(i%50)..'@realm',realm='realm',
  class='MAGE',postedAt=1,lastModified=1,ordinaryComplete=true,loadoutAvailable=true,
  echoes={{spellId=200001+(i%40),quality=1,stacks=1+(i%3)},{spellId=200050+(i%30),quality=2,stacks=1}},
  lockedEchoes={},lockedComplete=true}
end
local db=F.Database({version=2});db.communityBuilds={}
for i=1,N do db.communityBuilds['warm-'..i]=Record(i) end
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
check(C.Status().availableCount==N,'fixture: every row is admitted: '..C.Status().availableCount)

-- The canonical material, read from the catalog by this test with the cache's
-- own entry builders, hashed by the reference definition (sorted entries,
-- djb2 over their bytes, per bucket). The cache must produce these bytes.
local function find(f,needle,seen)
 if type(f)~='function' or seen[f] then return end;seen[f]=true
 for i=1,100 do local n,v=debug.getupvalue(f,i);if not n then break end
  if n==needle then return v end
  if n~='_ENV' and type(v)=='function' then local got=find(v,needle,seen);if got then return got end end
 end
end
local BuildEntry=assert(find(Cache.Pump,'BuildEntry',{}),'cache BuildEntry')
local TombstoneEntry=assert(find(Cache.Pump,'TombstoneEntry',{}),'cache TombstoneEntry')
local function Reference(mode)
 local buckets={};for b=1,8 do buckets[b]={} end
 local token=assert(C.BeginSummaryCursor(),'reference summary cursor')
 for _=1,100000 do
  local summary,done,err=C.SummaryCursorNext(token)
  assert(not err,tostring(err))
  if type(summary)=='table' and (mode=='legacy' or summary.syncDelta) then
   local bucket=buckets[Cache.Bucket(summary.id)];bucket[#bucket+1]=BuildEntry(summary.id,summary)
  end
  if done then break end
 end
 local cursor
 for _=1,100000 do
  local id,tomb,done=C.TombstoneNext(cursor)
  if done or id==nil then break end
  local bucket=buckets[Cache.Bucket(id)];bucket[#bucket+1]=TombstoneEntry(id,tomb);cursor=id
 end
 local out={}
 for b=1,8 do
  table.sort(buckets[b]);local v=5381
  for _,s in ipairs(buckets[b]) do for i=1,#s do v=((v*33)+s:byte(i))%2147483648 end end
  out[b]=#buckets[b]>0 and string.format('%x',v) or '0'
 end
 return table.concat(out,',')
end
local function Exact(label)
 check(Cache.Delta()==Reference('delta'),label..': the delta digest is the canonical bytes')
 check(Cache.Legacy()==Reference('legacy'),label..': the legacy digest is the canonical bytes')
end
check(Cache.Legacy():find('[1-9a-f]')~=nil,'fixture: the legacy digest carries real hashes: '..tostring(Cache.Legacy()))
Exact('start-up')

-- 1. A full warm-up on an idle catalog finishes within a bounded number of
-- frames (one lifecycle update each), with bounded work per pump.
local before=Cache.Stats()
Rev.Advance(EVENT,{scope='all',reason='test cold'})
check(not Ready() and Cache.Delta()==nil,'an all-scope revision makes the cache cold and nothing is served while it prepares')
local frames=Frames(Ready)
local after=Cache.Stats()
check(frames<=N/8+40,'a '..N..'-row warm-up is ready within '..(N/8+40)..' frames: '..frames)
check(after.buildRows==N,'every row was collected: '..tostring(after.buildRows))
check((after.maxWarmRowsPerPump or 0)<=after.warmRowBudget and (after.maxHashWorkPerPump or 0)<=after.hashWorkBudget,
 'per-pump work stayed within the stated budgets: rows '..tostring(after.maxWarmRowsPerPump)..'/'..tostring(after.warmRowBudget)
 ..' hash '..tostring(after.maxHashWorkPerPump)..'/'..tostring(after.hashWorkBudget))
check(after.fullRebuilds==before.fullRebuilds+1 and after.warmRestarts==before.warmRestarts,'one complete rebuild, no restart')
Exact('after the cold warm-up')

-- 2. Idle: no revision, no work.
before=Cache.Stats()
for _=1,60 do check(Cache.Pump()==true,'an idle pump answers ready at once');H.Advance(.05,.05) end
after=Cache.Stats()
check(after.warmPumps==before.warmPumps and after.hashPumps==before.hashPumps,'idle frames do no cache work')

-- 3. A record-scope revision during the hashing phase is absorbed: the
-- collected rows are kept, the named record is re-read, only its buckets
-- are re-hashed, and the digest still equals the canonical bytes.
local function Hashing() local s=Cache.Stats();return s.pending and s.phase~='summary' and s.phase~='tombstone' end
Rev.Advance(EVENT,{scope='all',reason='test absorb'})
Frames(Hashing)
before=Cache.Stats()
Rev.Advance(EVENT,{scope='record',id='warm-7',reason='test record revision while hashing'})
Frames(Ready)
after=Cache.Stats()
check(after.warmRestarts==before.warmRestarts and after.collectionWalks==before.collectionWalks,
 'the walk was not restarted by a record-scope revision during hashing')
check(after.targetedInvalidations==before.targetedInvalidations+1,'the named record was updated in place')
check(Cache.Stats().revision==Rev.Get(EVENT),'the cache observed the latest revision')
Exact('after an absorbed record revision')

-- 4. A real admission while the walk runs restarts the walk (the cursor is
-- stale on the new root); readiness is still reached and the digest covers
-- the new row.
Rev.Advance(EVENT,{scope='all',reason='test walk restart'})
H.Advance(.05,.05)
check(Cache.Stats().phase=='summary','fixture: the walk is in progress')
before=Cache.Stats()
local ok,why,ticket=C.Put(Record(N+1),{source='sync'})
if ok==nil and type(ticket)=='table' then Frames(function() return ticket.state~='pending' end) end
check(C.Get('warm-'..(N+1))~=nil,'fixture: the row was admitted during the walk: '..tostring(why))
Frames(Ready)
after=Cache.Stats()
check(after.warmRestarts>=before.warmRestarts+1,'the walk restarted on the new root: '..after.warmRestarts..' vs '..before.warmRestarts)
check(after.buildRows==N+1,'the restarted walk collected the new row too')
Exact('after a restart')

-- 5. Fail closed: an all-scope revision and an id-less record revision during
-- hashing reset the preparation; a catalog identity change does too.
for _,detail in ipairs({{scope='all',reason='test reset all'},{scope='record',reason='test reset without id'}}) do
 Rev.Advance(EVENT,{scope='all',reason='test prepare'})
 Frames(Hashing)
 before=Cache.Stats()
 Rev.Advance(EVENT,detail)
 Frames(Ready)
 after=Cache.Stats()
 check(after.collectionWalks>before.collectionWalks,detail.reason..': the preparation restarted from the catalog')
 Exact(detail.reason)
end
Rev.Advance(EVENT,{scope='all',reason='test identity'})
Frames(Hashing)
before=Cache.Stats()
local real=Nexus.BuildCatalog
Nexus.BuildCatalog=setmetatable({},{__index=real})
H.Advance(.05,.05)
Nexus.BuildCatalog=real
Frames(Ready)
after=Cache.Stats()
check(after.collectionWalks>before.collectionWalks,'a catalog identity change resets the preparation')
Exact('after an identity reset')

-- 6. Once ready, an admission is a targeted update whose re-hash is bounded.
before=Cache.Stats()
ok,why,ticket=C.Put(Record(N+2),{source='sync'})
if ok==nil and type(ticket)=='table' then Frames(function() return ticket.state~='pending' end) end
frames=Frames(Ready)
after=Cache.Stats()
check(after.targetedInvalidations==before.targetedInvalidations+1 and after.fullInvalidations==before.fullInvalidations,
 'an admission once ready is a targeted update, not a rebuild')
check(frames<=12,'the targeted re-hash is ready within 12 frames: '..frames)
Exact('after a targeted update')
print('PASS hash_cache_warm_budget rows='..N..' checks='..checks)
