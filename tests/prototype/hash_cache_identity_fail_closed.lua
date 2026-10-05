-- The build-hash cache answers (readiness, both digests, bucket marker
-- authority, targeted updates) only for the source its rows came from: the
-- catalog object, the database it serves and its binding generation. A
-- replacement catalog (even one serving the same revision), a removed or
-- unreadable one, a record-scope revision published on a replacement, and a
-- rebind of the catalog to another root all fail closed BEFORE any answer:
-- nothing old is served, old and new rows never blend, and a fresh
-- collection follows. A legitimate record update on the same source stays a
-- targeted update. Ready and still-preparing states both. Real TOC boot,
-- real catalog, real revision bus and rebind contract; synthetic rows.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local N=48
local function Record(i)
 local name='Peer'..(i%12)
 return {id='src-'..i,title='Source '..i,author=name,ownerKey=name:lower()..'@realm',realm='realm',ownerVerified=true,
  class='MAGE',postedAt=1,lastModified=1,ordinaryComplete=true,loadoutAvailable=true,
  echoes={{spellId=200001+(i%40),quality=1,stacks=1+(i%3)},{spellId=200050+(i%30),quality=2,stacks=1}},
  lockedEchoes={},lockedComplete=true}
end
local db=F.Database({version=2});db.communityBuilds={};db.syncTombstones={}
for i=1,N do db.communityBuilds['src-'..i]=Record(i) end
for i=1,8 do db.syncTombstones['gone-'..i]={stamp=i,author='Peer'..i} end
local H=F.Boot(db)
local C,Cache,Rev=Nexus.BuildCatalog,Nexus.BuildHashCache,Nexus.Revisions
local EVENT=Rev.BUILD_LIBRARY_CHANGED
local function Frames(predicate,limit)
 local n=0
 for _=1,limit or 20000 do H.Advance(.05,.05);n=n+1;if predicate() then return n end end
 error('bounded wait did not reach its condition after '..n..' frames')
end
local function Ready() return Cache.Stats().phase=='ready' end
local function Hashing() local s=Cache.Stats();return s.pending and s.phase~='summary' and s.phase~='tombstone' end
Frames(Ready)
check(C.Status().availableCount==N and C.Status().tombstoneCount==8,'fixture: every row and marker is admitted')

local function find(f,needle,seen)
 if type(f)~='function' or seen[f] then return end;seen[f]=true
 for i=1,100 do local n,v=debug.getupvalue(f,i);if not n then break end
  if n==needle then return v end
  if n~='_ENV' and type(v)=='function' then local got=find(v,needle,seen);if got then return got end end
 end
end
local BuildEntry=assert(find(Cache.Pump,'BuildEntry',{}),'cache BuildEntry')
local TombstoneEntry=assert(find(Cache.Pump,'TombstoneEntry',{}),'cache TombstoneEntry')
-- The canonical material of whatever catalog object serves now.
local function Reference(mode)
 local catalog=Nexus.BuildCatalog
 local buckets={};for b=1,8 do buckets[b]={} end
 local token=assert(catalog.BeginSummaryCursor(),'reference summary cursor')
 for _=1,100000 do
  local summary,done,err=catalog.SummaryCursorNext(token)
  assert(not err,tostring(err))
  if type(summary)=='table' and (mode=='legacy' or summary.syncDelta) then
   local bucket=buckets[Cache.Bucket(summary.id)];bucket[#bucket+1]=BuildEntry(summary.id,summary)
  end
  if done then break end
 end
 local cursor
 for _=1,100000 do
  local id,tomb,done=catalog.TombstoneNext(cursor)
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
Exact('start-up')
local realCatalog=Nexus.BuildCatalog
local known=Cache.Legacy()
check(known:find('[1-9a-f]')~=nil,'fixture: the digest carries real hashes')

-- Nothing is served for the current (replaced or removed) catalog.
local function Refused(label)
 check(Cache.Pump()==false,label..': the pump does not answer ready')
 check(Cache.Delta()==nil and Cache.Legacy()==nil,label..': neither digest is served')
 check(Cache.BucketHasTombstone(1)==nil,label..': marker authority is not served')
 check(Cache.Stats().initialized==false and Cache.Stats().phase~='ready',label..': the cache is not ready')
end
local function Restored(label)
 Nexus.BuildCatalog=realCatalog
 local before=Cache.Stats()
 Frames(Ready)
 check(Cache.Stats().collectionWalks>before.collectionWalks or before.collectionWalks>0,label..': a fresh collection followed')
 check(Cache.Stats().sourceAgrees==true,label..': the rows come from the serving source')
 Exact(label)
end

-- 1. Ready, then the catalog is replaced by an unreadable table (the
-- reviewer's case): no readiness, no digest, no marker authority.
local before=Cache.Stats()
Nexus.BuildCatalog={}
Refused('unreadable replacement while ready')
check(Cache.Stats().sourceInvalidations==before.sourceInvalidations+1,'the replacement was counted as a source invalidation')
Restored('after the unreadable replacement')

-- 2. Ready, then the catalog is removed.
Nexus.BuildCatalog=nil
Refused('removed catalog while ready')
Restored('after the removal')

-- 3. Ready, then a replacement that serves the same rows at the same revision
-- (another object): nothing old is served; a fresh collection from the
-- replacement is allowed and equals its canonical bytes; the real catalog
-- coming back is again a new source.
before=Cache.Stats()
local proxy=setmetatable({},{__index=realCatalog})
Nexus.BuildCatalog=proxy
check(Cache.Pump()==false and Cache.Delta()==nil and Cache.Legacy()==nil and Cache.BucketHasTombstone(1)==nil,
 'a same-revision replacement serves nothing from the old rows')
check(Cache.Stats().sourceInvalidations==before.sourceInvalidations+1,'the same-revision replacement was counted')
Frames(Ready)
check(Cache.Stats().collectionWalks>before.collectionWalks,'the replacement was collected afresh')
Exact('warmed from the replacement')
Restored('real catalog back after the replacement')

-- 4. A record-scope revision published while a replacement serves: the rows
-- are reset, never updated in place from the other source (no blending).
before=Cache.Stats()
Nexus.BuildCatalog=proxy
Rev.Advance(EVENT,{scope='record',id='src-3',reason='test record revision on a replacement'})
check(Cache.Stats().initialized==false,'a record revision on a replacement resets the rows')
check(Cache.Stats().targetedInvalidations==before.targetedInvalidations,'no row of the old collection was updated in place')
check(Cache.Delta()==nil and Cache.Legacy()==nil,'nothing is served after the reset')
Restored('after a record revision on a replacement')

-- 5. While the rows are still being hashed (not yet ready): the same
-- replacement, removal and record-revision-on-replacement rules.
local function Preparing()
 Rev.Advance(EVENT,{scope='all',reason='test prepare'})
 Frames(Hashing)
 check(Cache.Stats().initialized==false and Cache.Stats().pending==true,'fixture: the rows are collected and being hashed')
end
Preparing();before=Cache.Stats()
Nexus.BuildCatalog={}
Refused('unreadable replacement while preparing')
Restored('after the unreadable replacement while preparing')
Preparing()
Nexus.BuildCatalog=nil
Refused('removed catalog while preparing')
Restored('after the removal while preparing')
Preparing();before=Cache.Stats()
Nexus.BuildCatalog=proxy
Rev.Advance(EVENT,{scope='record',id='src-5',reason='test record revision on a replacement while preparing'})
check(Cache.Stats().pending==false and Cache.Stats().initialized==false,'a record revision on a replacement resets the preparation')
check(Cache.Stats().targetedInvalidations==before.targetedInvalidations,'no collected row was updated from the other source')
Restored('after a record revision on a replacement while preparing')

-- 6. A legitimate record update on the same source stays a targeted update
-- (ready, and while preparing).
before=Cache.Stats()
local ok,why,ticket=C.Put(Record(N+1),{source='sync'})
if ok==nil and type(ticket)=='table' then Frames(function() return ticket.state~='pending' end) end
check(C.Get('src-'..(N+1))~=nil,'fixture: the row is admitted: '..tostring(why))
Frames(Ready)
check(Cache.Stats().targetedInvalidations==before.targetedInvalidations+1 and Cache.Stats().fullInvalidations==before.fullInvalidations
 and Cache.Stats().sourceInvalidations==before.sourceInvalidations,'a same-source admission is a targeted update')
Exact('after a same-source targeted update')
Preparing();before=Cache.Stats()
Rev.Advance(EVENT,{scope='record',id='src-7',reason='test same-source record revision while hashing'})
Frames(Ready)
check(Cache.Stats().targetedInvalidations==before.targetedInvalidations+1 and Cache.Stats().collectionWalks==before.collectionWalks,
 'a same-source record revision while hashing is absorbed in place')
Exact('after a same-source record revision while hashing')

-- 7. The catalog rebound to another root through the supported coordinator
-- request (the catalog object stays, the database and binding change): the
-- cache never claims readiness for rows whose source no longer agrees, and
-- once the new root is admitted and warmed it serves that root's bytes.
local oldDigest=Cache.Legacy()
local fresh=F.Database({version=2});fresh.communityBuilds={};fresh.syncTombstones={['only-'..1]={stamp=1,author='Peer1'}}
for i=1,5 do fresh.communityBuilds['fresh-'..i]=Record(100+i);fresh.communityBuilds['fresh-'..i].id='fresh-'..i end
local oldBinding=C.ManualPreparationStatus().binding
NexusDB=fresh
check(C.RequestAuthorityRebindV1('SOURCE_REBIND_REQUIRED')~=nil,'fixture: a rebind is requested')
-- At every frame, whenever the catalog refuses its source at that moment,
-- every authority answer refuses too, and the old digest is never served
-- once the other root is bound (the lifecycle withholds the cache pump
-- while the catalog is not ready, so internal state is not the oracle; the
-- answers are).
local frames=0
for _=1,20000 do
 H.Advance(.05,.05);frames=frames+1
 local agrees=C.ManualPreparationStatus().ownerAgrees==true
 local legacy=Cache.Legacy()
 check(agrees or (legacy==nil and Cache.Pump()==false and Cache.BucketHasTombstone(1)==nil),'frame '..frames..': no answer while the catalog refuses its source')
 check(legacy==nil or legacy~=oldDigest,'frame '..frames..': the old digest is never served again')
 if not C.RebindRequired() and C.BoundDatabase()==fresh and C.ManualPreparationStatus().ready and Ready() then break end
end
check(C.BoundDatabase()==fresh and C.ManualPreparationStatus().binding~=oldBinding,'the catalog serves the new root under a new binding')
check(C.Get('fresh-1')~=nil and C.Get('src-1')==nil,'the new root holds the new rows and none of the old')
check(Cache.Legacy()~=oldDigest,'the old digest is gone')
Exact('after the rebind to another root')
print('PASS hash_cache_identity_fail_closed rows='..N..' checks='..checks)
