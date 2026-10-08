-- The build-hash cache answers (readiness, both digests, bucket marker
-- authority) only while the catalog itself agrees that the admitted root
-- still serves for the current saved root and owner
-- (ManualPreparationStatus().ownerAgrees; its refusal is
-- OWNER_OR_GENERATION_MISMATCH). The saved root replaced underneath the
-- catalog before any rebind was requested (the catalog still reports the
-- old bound database), the local owner changed, a saved map replaced in
-- place (source drift): each refuses every answer at once and retains
-- nothing, in the ready state, during the collection walk and while
-- hashing; the rows of a refused source are never served again, and the
-- old digest is never served once another root is bound. The ready flag
-- alone is not the contract: a same-source transaction that is still
-- pending keeps the serving root and the cache keeps answering for it.
-- The coordinator's own rebind (which the lifecycle requests on drift, or
-- a test requests explicitly) recovers the bytes of whatever root is then
-- served. Real TOC boot, real catalog, real revision bus and rebind
-- contract; synthetic rows.
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
 local s=Cache.Stats();local c=C.ManualPreparationStatus()
 error('bounded wait did not reach its condition after '..n..' frames (cache '..tostring(s.phase)..'/'..tostring(s.sourceRefusal)
  ..', catalog '..tostring(c.reason)..' agrees='..tostring(c.ownerAgrees)..' rebind='..tostring(C.RebindRequired())..')\n'..debug.traceback())
end
local function Ready() return Cache.Stats().phase=='ready' end
local function Hashing() local s=Cache.Stats();return s.pending and s.phase~='summary' and s.phase~='tombstone' end
Frames(Ready)
check(C.Status().availableCount==N and C.Status().tombstoneCount==8,'fixture: every row and marker is admitted')
local original=NexusDB
check(C.BoundDatabase()==original,'fixture: the catalog serves the saved root')
local markerBucket=Cache.Bucket('gone-1')

local function find(f,needle,seen)
 if type(f)~='function' or seen[f] then return end;seen[f]=true
 for i=1,100 do local n,v=debug.getupvalue(f,i);if not n then break end
  if n==needle then return v end
  if n~='_ENV' and type(v)=='function' then local got=find(v,needle,seen);if got then return got end end
 end
end
local BuildEntry=assert(find(Cache.Pump,'BuildEntry',{}),'cache BuildEntry')
local TombstoneEntry=assert(find(Cache.Pump,'TombstoneEntry',{}),'cache TombstoneEntry')
-- The canonical material of the root the catalog serves now.
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
Exact('start-up')
local known=Cache.Legacy()
check(known:find('[1-9a-f]')~=nil and Cache.Delta():find('[1-9a-f]')~=nil,'fixture: both digests carry real hashes')
check(Cache.BucketHasTombstone(markerBucket)==true,'fixture: the marker bucket reports its markers')

-- The catalog refuses its source (owner/source/generation mismatch): the
-- cache answers nothing at once and retains nothing. Over the frames that
-- follow, the lifecycle's coordinator may rebind to whatever root is current
-- (that is its contract); the cache is never ready for rows of a source the
-- catalog refuses, and when `otherRoot` is set the old digest is never served
-- while that other root is the one bound.
local function Refused(label,otherRoot)
 local status=C.ManualPreparationStatus()
 check(status.ownerAgrees==false and status.reason=='OWNER_OR_GENERATION_MISMATCH',label..': the catalog refuses its source: '..tostring(status.reason))
 check(Cache.Pump()==false,label..': the pump does not answer ready')
 check(Cache.Delta()==nil and Cache.Legacy()==nil,label..': neither digest is served')
 check(Cache.BucketHasTombstone(markerBucket)==nil,label..': marker authority is not served')
 local s=Cache.Stats()
 check(s.initialized==false and s.pending==false and s.phase=='cold',label..': nothing is retained and no collection runs: '..tostring(s.phase))
 check(s.sourceRefusal=='OWNER_OR_GENERATION_MISMATCH',label..': the refusal reason is reported: '..tostring(s.sourceRefusal))
 -- Every authority answer, whenever the catalog refuses at that moment,
 -- refuses too (the coordinator may change the catalog's state at any
 -- point of a frame; what matters is the answer given after it).
 for frame=1,12 do
  H.Advance(.05,.05)
  local agrees=C.ManualPreparationStatus().ownerAgrees==true
  local legacy=Cache.Legacy()
  check(agrees or (legacy==nil and Cache.Delta()==nil and Cache.Pump()==false and Cache.BucketHasTombstone(markerBucket)==nil),
   label..' frame '..frame..': no answer while the catalog refuses its source')
  if otherRoot then
   check(legacy==nil or legacy~=known,label..' frame '..frame..': the old digest is not served for another root')
  end
 end
end
-- The source agrees again (the original root bound once more, or the same
-- root re-admitted) with no rebind pending: the cache is ready for it and
-- serves the same canonical bytes.
local function Recovered(label)
 local before=Cache.Stats()
 Frames(function() return Ready() and C.ManualPreparationStatus().ownerAgrees==true and not C.RebindRequired() end)
 local status=C.ManualPreparationStatus()
 check(C.BoundDatabase()==original and status.ownerAgrees==true,label..': the catalog serves the original root and agrees with it (bound original='
  ..tostring(C.BoundDatabase()==original)..' agrees='..tostring(status.ownerAgrees)..' reason='..tostring(status.reason)..')')
 check(Cache.Stats().collectionWalks>before.collectionWalks or Cache.Stats().sourceAgrees==true,label..': the rows were collected from the agreed source')
 check(Cache.Stats().sourceAgrees==true and Cache.Stats().sourceRefusal==nil,label..': the source agrees')
 check(Cache.Legacy()==known,label..': the same material gives the same bytes')
 check(Cache.BucketHasTombstone(markerBucket)==true,label..': marker authority is served again')
 Exact(label)
end

-- 1. The saved root replaced underneath the catalog, nothing requested (the
-- reviewer's case): the catalog still reports the old bound database and
-- refuses its source; the cache serves nothing, never the old digest once
-- the fresh root is bound; the original root put back is served again.
local before=Cache.Stats()
NexusDB=F.Database({version=2})
check(C.BoundDatabase()==original,'the catalog still reports the old bound database before any rebind')
Refused('saved root swapped while ready',true)
check(Cache.Stats().sourceInvalidations>=before.sourceInvalidations+1,'the swap was counted as a source invalidation')
NexusDB=original
Refused('original root put back (another root is bound now)',false)
Recovered('after the saved root is restored')

-- 2. The same swap during the collection walk and while hashing.
Rev.Advance(EVENT,{scope='all',reason='test swap during the walk'})
H.Advance(.05,.05)
check(Cache.Stats().phase=='summary','fixture: the walk is in progress')
NexusDB=F.Database({version=2})
Refused('saved root swapped during the walk',true)
NexusDB=original
Recovered('after the restore during the walk')
Rev.Advance(EVENT,{scope='all',reason='test swap while hashing'})
Frames(Hashing)
NexusDB=F.Database({version=2})
Refused('saved root swapped while hashing',true)
NexusDB=original
Recovered('after the restore while hashing')

-- 3. The local owner changed (the admitted token names another owner), ready
-- and while hashing. The same root re-admitted under the new owner serves
-- the same bytes, so only the refusal itself is asserted over the frames.
-- An owner change is not a source drift the coordinator rebinds by itself:
-- the owner rebind is requested through the documented contract
-- (RequestAuthorityRebindV1('OWNER_REBIND_REQUIRED')), as the startup
-- coordinator does with a new owner proof.
local realUnitName=UnitName
UnitName=function() return 'Drifter','Ebonhold' end
Refused('local owner changed while ready',false)
UnitName=realUnitName
C.RequestAuthorityRebindV1('OWNER_REBIND_REQUIRED')
Recovered('after the owner is back')
Rev.Advance(EVENT,{scope='all',reason='test owner change while hashing'})
Frames(Hashing)
UnitName=function() return 'Drifter','Ebonhold' end
Refused('local owner changed while hashing',false)
UnitName=realUnitName
C.RequestAuthorityRebindV1('OWNER_REBIND_REQUIRED')
Recovered('after the owner is back while hashing')

-- 4. A saved map replaced in place (source drift: the admitted token names
-- the map object). The original map put back is a drift again; the source
-- rebind is requested through the documented contract.
local source=NexusDB.authorityBundle or NexusDB
local map=source.communityBuilds
local copy={};for k,v in pairs(map) do copy[k]=v end
source.communityBuilds=copy
Refused('saved overlay map replaced in place',false)
source.communityBuilds=map
C.RequestAuthorityRebindV1('SOURCE_REBIND_REQUIRED')
Recovered('after the original map is back')

-- 5. A same-source transaction that is still pending is not a refusal: the
-- serving root stays, and so does every answer; its commit is a targeted
-- update.
before=Cache.Stats()
local ok,why,ticket=C.Put(Record(N+1),{source='sync'})
check(ok==nil and type(ticket)=='table' and ticket.state=='pending','fixture: the admission is a pending catalog transaction: '..tostring(why))
local status=C.ManualPreparationStatus()
check(status.ownerAgrees==true and status.ready==false and status.reason=='CATALOG_COMMIT_PENDING','fixture: a same-source transaction is pending: '..tostring(status.reason))
check(Cache.Pump()==true,'a pending same-source transaction keeps readiness')
check(Cache.Delta()==Reference('delta') and Cache.Legacy()==Reference('legacy'),'and keeps serving the canonical bytes of the serving root')
check(Cache.BucketHasTombstone(markerBucket)==true,'and keeps marker authority')
check(Cache.Stats().sourceAgrees==true and Cache.Stats().sourceRefusal==nil,'the source agrees throughout')
Frames(function() return ticket.state~='pending' end)
check(C.Get('src-'..(N+1))~=nil,'fixture: the transaction committed')
Frames(Ready)
local after=Cache.Stats()
check(after.targetedInvalidations==before.targetedInvalidations+1 and after.fullInvalidations==before.fullInvalidations
 and after.sourceInvalidations==before.sourceInvalidations,'the commit was a targeted update, not a refusal')
Exact('after the pending transaction committed')
known=Cache.Legacy()

-- 6. The saved root replaced, then the coordinator rebind requested
-- explicitly: nothing old is served at any frame, and the new root's bytes
-- are served once it is admitted and collected.
local fresh=F.Database({version=2});fresh.communityBuilds={};fresh.syncTombstones={['only-1']={stamp=1,author='Peer1'}}
for i=1,5 do fresh.communityBuilds['fresh-'..i]=Record(100+i);fresh.communityBuilds['fresh-'..i].id='fresh-'..i end
NexusDB=fresh
check(C.ManualPreparationStatus().ownerAgrees==false and Cache.Pump()==false and Cache.Legacy()==nil and Cache.BucketHasTombstone(markerBucket)==nil,
 'saved root swapped before the requested rebind: refused at once')
check(C.RequestAuthorityRebindV1('SOURCE_REBIND_REQUIRED')~=nil,'fixture: the rebind is requested')
local frames=0
for _=1,20000 do
 H.Advance(.05,.05);frames=frames+1
 local agrees=C.ManualPreparationStatus().ownerAgrees==true
 local legacy=Cache.Legacy()
 check(agrees or (legacy==nil and Cache.Pump()==false and Cache.BucketHasTombstone(markerBucket)==nil),'frame '..frames..': no answer while the catalog refuses its source')
 check(legacy==nil or legacy~=known,'frame '..frames..': the old digest is never served again')
 if not C.RebindRequired() and C.BoundDatabase()==fresh and C.ManualPreparationStatus().ready and Ready() then break end
end
check(C.BoundDatabase()==fresh and C.Get('fresh-1')~=nil and C.Get('src-1')==nil,'the catalog serves the new root')
check(Cache.Legacy()~=known and Cache.Legacy():find('[1-9a-f]')~=nil,'the new root has its own digest')
Exact('after the requested rebind')
print('PASS hash_cache_source_refusal rows='..N..' checks='..checks)
