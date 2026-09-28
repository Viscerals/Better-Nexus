-- DPS sync digest: prepared in bounded steps, never advertised partial or
-- stale. Real TOC boot, real owners (DpsCapture, LoadoutEvidence, Revisions,
-- MainLifecycle hash slot, Sync), real inbound DPS records; synthetic data.
--
-- After a full invalidation the digest is rebuilt by one job pumped once per
-- lifecycle update. Until it publishes, GetSyncHash and the Sync wire hash
-- are nil and no response bucket can be claimed. The published digest equals
-- the uncached canonical digest (GetSyncHashUncached) of the same store.
-- Record-scoped changes during the job are revisited, not restarted; a store
-- replacement or an unscoped revision restarts it. A manual Sync request waits
-- in its "preparing" state instead of sending a false digest.
--
-- Assertions count operations and frames; no wall-clock threshold. DSD_N sets
-- the number of filler characters (default 240).
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local N=tonumber(os.getenv('DSD_N') or '') or 240
local CLAIMS_PER_PUMP=8
local checks=0
local function check(v,m) if not v then error(m,2) end;checks=checks+1 end

local players={{name='PrototypeTester',class='MAGE',dps={lk=39000,dummy=38000},isLocal=true,variant=30,ordinary=60},
 {name='Alpha',class='MAGE',dps={lk=52000,dummy=48000},variant=10,ordinary=60}}
for i=1,N do players[#players+1]={name='Filler'..i,class='PRIEST',variant=100+i,dps={lk=20000+i,dummy=19000+i}} end
local fx=L.New({players=players})
local H=F.Boot(fx:Install(F.Database({version=2})),function(h) h.playerLevel=60 end)
local D=Nexus.DpsCapture
local function Frames(n,each) for i=1,n do if each then each(i) end;H.Advance(.05,.05) end end
-- Builds without the bounded digest report no phase: ready once initialized.
local function Phase() local s=D.HashCacheStats();return s.phase or (s.initialized and 'ready' or 'cold') end
local function Stats() return D.HashCacheStats() end
local function WireDps() local _,dps=Nexus.Sync.GetCompatibilityHashes();return dps end

-- Evidence work inside each lifecycle digest pump (call-through wrappers).
local Ev=Nexus.LoadoutEvidence
local resolve=Ev.Resolve
local inPump,perPump,maxPerPump,pumps=false,0,0,0
Ev.Resolve=function(...) if inPump then perPump=perPump+1 end;return resolve(...) end
local pump=D.PumpSyncHash
-- Readiness contract: when a pump reports ready, the digest is readable in
-- the same frame (the Sync gate opens on that report and reads it at once).
local readyWithoutHash=0
D.PumpSyncHash=function(...)
 inPump,perPump=true,0
 local ready,progressed=pump(...)
 inPump=false;pumps=pumps+1
 if perPump>maxPerPump then maxPerPump=perPump end
 if ready and D.GetSyncHash()==nil then readyWithoutHash=readyWithoutHash+1 end
 return ready,progressed
end

local jobFrames -- measured length of one full job (section 2)
local function UntilReady(limit,each)
 for i=1,limit or 20000 do
  if Phase()=='ready' then return i end
  if each then each(i) end
  H.Advance(.05,.05)
 end
 return nil
end

-- 1. Start-up: the digest becomes ready through the lifecycle slot and
-- equals the canonical digest.
check(UntilReady(40000),'1: the start-up digest becomes ready: '..tostring(Phase()))
check(D.GetSyncHash()==D.GetSyncHashUncached(),'1: the digest equals the canonical digest')
check(WireDps()==D.GetSyncHash(),'1: the Sync wire hash is the digest')

-- 2. A full invalidation: nothing is advertised until the bounded job
-- publishes; every pump does at most ROWS_PER_PUMP evidence resolutions; the
-- work spans several updates; the published digest is canonical.
do
 local restarts0=Stats().jobRestarts
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{scope='test'})
 check(D.GetSyncHash()==nil,'2: not ready right after a full invalidation (no synchronous rebuild)')
 check(WireDps()==nil,'2: the Sync wire hash is nil, not "0", while not ready')
 check(D.ResponseBucketClaimInfo(1)==false,'2: no bucket can be claimed while not ready')
 maxPerPump,pumps=0,0
 local advertised=0
 local frames=UntilReady(20000,function()
  if D.GetSyncHash()~=nil then advertised=advertised+1 end
 end)
 print('DSD invalidation','N',N,'frames',frames,'pumps',pumps,'maxResolvesPerPump',maxPerPump,'maxRowsPerPump',Stats().maxRowsPerPump,'maxUnitsPerPump',Stats().maxUnitsPerPump)
 jobFrames=frames
 check(frames and frames>1,'2: the rebuild spans more than one update: '..tostring(frames))
 check(advertised==0,'2: no digest was advertised before the job published: '..advertised)
 check(maxPerPump<=CLAIMS_PER_PUMP,'2: evidence work per pump is bounded: '..maxPerPump)
 check(Stats().maxRowsPerPump<=256 and Stats().maxKeysPerPump<=4096 and Stats().maxUnitsPerPump<=2048,'2: rows, keys and hash units per pump are bounded')
 check(D.GetSyncHash()==D.GetSyncHashUncached(),'2: the published digest is canonical')
 check(Stats().jobRestarts==restarts0,'2: no restart without a source change')
end

-- 2b. Response claims follow the digest in bounded steps: a bucket is not
-- claimable until its claim is prepared, then it equals the synchronous
-- claim of the same store.
do
 local early=0
 for b=1,8 do if D.ResponseBucketClaimInfo(b)~=false then early=early+1 end end
 check(Stats().claimBucketsReady<8 or early==0,'2b: no bucket is claimable before its claim is prepared')
 maxPerPump=0
 for _=1,20000 do if Stats().claimBucketsReady==8 then break end;H.Advance(.05,.05) end
 check(Stats().claimBucketsReady==8,'2b: every bucket claim is prepared')
 check(maxPerPump<=CLAIMS_PER_PUMP,'2b: claim evidence per pump is bounded: '..maxPerPump)
 for b=1,8 do
  local c1,a1=D.ResponseBucketClaimInfo(b)
  local c2,a2=D.ResponseBucketClaimInfoUncached(b)
  check(c1==c2 and a1==a2,'2b: bucket '..b..' claim equals the synchronous claim')
 end
end

-- 3. Record-scoped changes during the job (updates of existing rows whose
-- build pages already exist, so no catalog commit replaces the saved store)
-- are revisited, not restarted, and appear in the digest. (A record that
-- creates a build page leads to a catalog commit that replaces the store:
-- sections 4, 5 and 5b.)
do
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{scope='test'})
 D.GetSyncHash()
 local restarts0=Stats().jobRestarts
 local sawRows=false
 for _=1,2000 do if Phase()=='rows' then sawRows=true;break end;H.Advance(.05,.05) end
 check(sawRows,'3: setup: the job reached its rows phase')
 local payload=rawget(rawget(NexusDB,'authorityBundle'),'dpsCapture')
 check(fx:Receive('Filler1','dummy',{dps=50001,ts=L.STAMP+901}),'3: setup: Filler1 update accepted')
 H.Advance(.05,.05)
 check(fx:Receive('Filler2','lk',{dps=50002,ts=L.STAMP+902}),'3: setup: Filler2 update accepted')
 check(D.GetSyncHash()==nil,'3: still not ready after the changes')
 check(UntilReady(20000),'3: the job completes')
 check(rawget(rawget(NexusDB,'authorityBundle'),'dpsCapture')==payload,'3: setup: the saved store was not replaced')
 check(Stats().jobRestarts==restarts0,'3: record-scoped changes do not restart the job')
 check(D.GetSyncHash()==D.GetSyncHashUncached(),'3: the digest includes both changes (canonical)')
end

-- 4. A change during the keys walk starts that walk again (a table may not
-- gain keys while `next` walks it): (a) an update of an existing row restarts
-- the keys walk; (b) a new player restarts the keys walk or, when its build
-- page commit replaces the store, the whole job. The result is canonical.
do
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{scope='test'})
 D.GetSyncHash()
 check(Phase()=='keys','4a: setup: the job starts in its keys walk')
 local keyRestarts=Stats().keyRestarts
 check(fx:Receive('Filler3','dummy',{dps=50003,ts=L.STAMP+903}),'4a: setup: an update accepted')
 check(UntilReady(20000),'4a: the job completes')
 check(Stats().keyRestarts>keyRestarts,'4a: the keys walk started again')
 check(D.GetSyncHash()==D.GetSyncHashUncached(),'4a: the digest is canonical')
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{scope='test'})
 D.GetSyncHash()
 check(Phase()=='keys','4b: setup: the job starts in its keys walk')
 local k0,j0=Stats().keyRestarts,Stats().jobRestarts
 check(D.ReceiveRecord({v=7,c='lk',d=44444,u=120,t=time()-4,p='Latecomer',l=80,k='MAGE',
  o='latecomer@ebonhold',r='Ebonhold',e=L.Copy(fx.players[2].dpsOrdinary),f=fx.players[2].fingerprint,
  lk=L.Copy(fx.players[2].dpsLocked)},'Latecomer-Ebonhold'),'4b: setup: a new player record accepted')
 check(UntilReady(20000),'4b: the job completes')
 check(Stats().keyRestarts>k0 or Stats().jobRestarts>j0,'4b: the walk (or the job) started again')
 check(D.GetSyncHash()==D.GetSyncHashUncached(),'4b: the digest includes the new player (canonical)')
end

-- 5. The DPS store is replaced during the job by a copy whose content
-- differs without a DPS revision (as a maintenance commit can): the job
-- restarts on the new store and the digest describes the new content.
do
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{scope='test'})
 D.GetSyncHash()
 for _=1,2000 do if Phase()=='rows' then break end;H.Advance(.05,.05) end
 local restarts0=Stats().jobRestarts
 local bundle=rawget(NexusDB,'authorityBundle')
 check(type(bundle)=='table' and type(rawget(bundle,'dpsCapture'))=='table','5: setup: saved DPS payload')
 local function Copy(v,seen) if type(v)~='table' then return v end;seen=seen or {};if seen[v] then return seen[v] end
  local o={};seen[v]=o;for k,x in pairs(v)do o[Copy(k,seen)]=Copy(x,seen) end;return o end
 local copy=Copy(rawget(bundle,'dpsCapture'))
 local changed=0
 for _,category in ipairs({'dummy','lk'}) do
  for _,row in pairs(((copy.characterBest or {})[category]) or {}) do
   if changed<3 and type(row)=='table' and tostring(row.player):match('^Filler') then row.dps=row.dps+7;changed=changed+1 end
  end
 end
 check(changed==3,'5: setup: the copy differs in three rows')
 rawset(bundle,'dpsCapture',copy)
 check(UntilReady(20000),'5: the job completes on the new store')
 check(Stats().jobRestarts>restarts0,'5: the replacement restarted the job')
 check(D.GetSyncHash()==D.GetSyncHashUncached(),'5: the digest belongs to the new store (canonical)')
end

-- 5b. Store replacements during the job (as catalog commits replace the
-- saved payload) restart it; a restart costs one job length, so with a
-- replacement every (job length + 3) updates the digest still becomes ready.
do
 local function Copy(v,seen) if type(v)~='table' then return v end;seen=seen or {};if seen[v] then return seen[v] end
  local o={};seen[v]=o;for k,x in pairs(v)do o[Copy(k,seen)]=Copy(x,seen) end;return o end
 local bundle=rawget(NexusDB,'authorityBundle')
 local replaced=0
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{scope='test'})
 D.GetSyncHash()
 local frames=UntilReady(20000,function(i)
  if replaced<3 and i%(jobFrames+3)==math.max(1,jobFrames-2) then rawset(bundle,'dpsCapture',Copy(rawget(bundle,'dpsCapture')));replaced=replaced+1 end
 end)
 print('DSD replacements','frames',frames,'replacements',replaced,'jobFrames',jobFrames)
 check(frames,'5b: the digest becomes ready between store replacements')
 check(replaced>=1,'5b: setup: at least one replacement landed during the job')
 check(D.GetSyncHash()==D.GetSyncHashUncached(),'5b: the digest is canonical')
end

-- 6. Sustained record-scoped input (an update of an existing row every other
-- update, no catalog commit, faster than a bucket rebuild): the job still
-- publishes its generation while the input continues (no restart), later
-- changes are applied in bounded steps, and after the input stops the digest
-- converges to the canonical digest. While changes arrive faster than they
-- can be hashed the digest is truthfully not ready (reported, not asserted).
do
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{scope='test'})
 D.GetSyncHash()
 local restarts0,rebuilds0=Stats().jobRestarts,Stats().fullRebuilds
 local dps,sent,readyFrames,published,stale=60000,0,0,nil,0
 for i=1,math.max(120,4*jobFrames) do
  if i%2==0 then dps=dps+100;sent=sent+1;assert(fx:Receive('Filler'..(1+sent%5),'lk',{dps=dps,ts=time()-1}),'fixture: record accepted') end
  H.Advance(.05,.05)
  if not published and Stats().fullRebuilds>rebuilds0 then published=i end
  local digest=D.GetSyncHash()
  if digest~=nil then
   readyFrames=readyFrames+1
   if digest~=D.GetSyncHashUncached() then stale=stale+1 end
  end
 end
 print('DSD sustained','records',sent,'publishedAtFrame',tostring(published),'readyFrames',readyFrames,'of',math.max(120,4*jobFrames))
 check(published,'6: the job publishes its generation while record input continues')
 check(stale==0,'6: every digest returned during the input was canonical: '..stale..' stale')
 check(Stats().jobRestarts==restarts0,'6: record-scoped input does not restart the job')
 local converged=UntilReady(20000)
 check(converged,'6: after the input stops the digest converges')
 check(D.GetSyncHash()==D.GetSyncHashUncached(),'6: the converged digest is canonical')
end

-- 7. After publication a record-scoped change makes one bucket not ready
-- until the bounded bucket pump rebuilds it; no older value is returned.
do
 check(fx:Receive('Filler1','dummy',{dps=99999,ts=L.STAMP+950}),'7: setup: a record accepted')
 local advertisedStale,frames=0,0
 for i=1,2000 do
  local digest=D.GetSyncHash()
  if digest~=nil then
   if digest~=D.GetSyncHashUncached() then advertisedStale=advertisedStale+1 end
   frames=i;break
  end
  H.Advance(.05,.05)
 end
 check(frames>0,'7: the changed bucket is rebuilt')
 check(advertisedStale==0,'7: no stale digest was returned')
end

-- 8. Sync waits: while the digest is not ready the lifecycle Sync gate is
-- closed on the hashes, and a manual Sync Now is "preparing"; once ready the
-- request carries the canonical DPS digest.
do
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{scope='test'})
 D.GetSyncHash()
 H.Advance(.05,.05)
 local gate=Nexus.StartupStatus().syncGate
 check(gate=='hashes-not-ready' or Phase()=='ready','8: the Sync gate waits for the digest: '..tostring(gate))
 local sentBefore,chat0=#H.sent,#H.chat
 check(Phase()~='ready','8: setup: the digest is not ready')
 SlashCmdList.NEXUS('sync')
 local preparing=false
 for i=chat0+1,#H.chat do if tostring(H.chat[i]):find('preparing sync data',1,true) then preparing=true end end
 check(preparing,'8: a manual request waits ("preparing sync data") while the digest is prepared')
 check(UntilReady(20000),'8: the digest becomes ready')
 local wlrq
 for _=1,400 do
  for i=sentBefore+1,#H.sent do
   local text=tostring(H.sent[i].text):gsub('||','|')
   if text:match('^P?%d*:?WLRQ|') or text:match('WLRQ|') then wlrq=text end
  end
  if wlrq then break end
  H.Advance(.05,.05)
 end
 check(wlrq~=nil,'8: the manual request is sent after the digest is ready')
 check(wlrq:find(D.GetSyncHashUncached(),1,true)~=nil,'8: the request carries the canonical DPS digest')
end

-- The digest owner's budgets, for sections 9 and 10 (test-only access).
local Digest
for i=1,200 do
 local n,v=debug.getupvalue(pump,i)
 if n==nil then break end
 if n=='DpsDigest' then Digest=v;break end
end

-- 9. The claim walk: a row the walk already passed is changed in place (a
-- record-scoped metadata change, as owner/realm enrichment does). The walk
-- starts that bucket again, so the published claim matches the uncached
-- claim instead of keeping the evidence it read before the change.
do
 check(type(Digest)=='table','9: fixture: the digest owner is reachable')
 check(UntilReady(40000),'9: setup: the digest is ready')
 for _=1,20000 do if Stats().claimBucketsReady==8 then break end;H.Advance(.05,.05) end
 local target
 for b=1,8 do if D.ResponseBucketClaimInfoUncached(b) then target=b;break end end
 -- At the default size every bucket is claimable here. At other sizes no
 -- bucket may be, and then this section has nothing to exercise: it says so
 -- instead of passing silently.
 if N==240 then check(target~=nil,'9: fixture: some bucket is claimable') end
 if not target then print('DSD 9 NOT EXERCISED: no claimable bucket at N='..N) end
 if target then
  local function StoreRows() return rawget(rawget(NexusDB,'authorityBundle'),'dpsCapture').characterBest end
  Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{scope='test'})
  D.GetSyncHash()
  check(UntilReady(40000),'9: setup: the digest is ready again')
  local mutated
  for _=1,20000 do
   local job=Digest.claimJob
   if job and job.bucket==target and job.count>=1 and job.key~=nil then
    local entryKey=job.key
    local sep=entryKey:find('|',1,true)
    local cat,key=entryKey:sub(1,sep-1),entryKey:sub(sep+1)
    local row=StoreRows()[cat][key]
    check(row~=nil,'9: fixture: the walked row exists')
    row.level=0
    Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{scope='metadata',category=cat,
     player=row.player,ownerKey=row.ownerKey,realm=row.realm,characterKey=key})
    mutated=entryKey;break
   end
   H.Advance(.05,.05)
  end
  check(mutated~=nil,'9: setup: a walked row was changed during the claim walk')
  for _=1,20000 do
   local s=Stats()
   if s.claimBucketsReady==8 and s.dirtyBuckets==0 and Phase()=='ready' then break end
   H.Advance(.05,.05)
  end
  local c1,a1=D.ResponseBucketClaimInfo(target)
  local c2,a2=D.ResponseBucketClaimInfoUncached(target)
  check(c1==c2 and a1==a2,'9: the claim after the walk matches the uncached claim: '
   ..tostring(c1)..'/'..tostring(a1)..' vs '..tostring(c2)..'/'..tostring(a2))
  check(D.GetSyncHash()==D.GetSyncHashUncached(),'9: the digest is canonical')
 end
end

-- 10. Ordinary DPS traffic does not hold Sync back: with existing rows
-- improving at 2 and 10 records per second (no catalog commit), a changed
-- bucket within the one-call size is rebuilt in the same update, so the Sync
-- gate is never closed on the hashes (as before the bounded digest). The
-- bounded pump's unit budget is lowered for this section so that, at this
-- store size, a bucket rebuild through that pump takes several updates, as it
-- does at about 2000 builds; the immediate rebuild must not depend on it.
do
 local units=Digest.UNITS_PER_PUMP
 Digest.UNITS_PER_PUMP=16
 check(UntilReady(40000),'10: setup: the digest is ready')
 for _=1,400 do if Nexus.StartupStatus().syncGate=='open' then break end;H.Advance(.05,.05) end
 check(Nexus.StartupStatus().syncGate=='open','10: setup: the Sync gate is open: '..tostring(Nexus.StartupStatus().syncGate))
 local n=0
 for _,period in ipairs({10,2}) do
  local notReady,accepted,stale=0,0,0
  for i=1,600 do
   if i%period==0 then
    n=n+1
    local name='Filler'..(1+n%N)
    if fx:Receive(name,'dummy',{dps=90000+n,ts=time()-1}) then accepted=accepted+1 end
   end
   H.Advance(.05,.05)
   if Nexus.StartupStatus().syncGate=='hashes-not-ready' then notReady=notReady+1 end
   local digest=D.GetSyncHash()
   if digest~=nil and digest~=D.GetSyncHashUncached() then stale=stale+1 end
  end
  print('DSD traffic','period',period,'accepted',accepted,'hashes-not-ready frames',notReady,'of 600')
  check(accepted>=600/period-1,'10: fixture: records accepted at period '..period..': '..accepted)
  check(notReady==0,'10: the Sync gate is never closed on the hashes at '..(20/period)..' records/s: '..notReady..' of 600 frames')
  check(stale==0,'10: no stale digest at '..(20/period)..' records/s: '..stale)
 end
 Digest.UNITS_PER_PUMP=units
end

check(#H.actions==0,'zero gameplay mutation')
-- 10. A record change queued in the job's last (hash) phase: the job
-- publishes its snapshot with that change still pending. The pump that
-- publishes must not report ready before the change is applied, or Sync
-- reads no digest in the frame it was told the digest is ready.
do
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{scope='test'})
 D.GetSyncHash()
 local sawHash=false
 for _=1,4000 do if Phase()=='hash' then sawHash=true;break end;H.Advance(.05,.05) end
 check(sawHash,'10: setup: the job reached its hash phase')
 check(fx:Receive('Filler4','lk',{dps=70004,ts=time()-1}),'10: setup: Filler4 update accepted')
 local before=readyWithoutHash
 check(UntilReady(20000),'10: the digest becomes ready')
 check(readyWithoutHash==before,'10: no pump reported ready while the digest was unreadable: '..(readyWithoutHash-before))
 check(D.GetSyncHash()==D.GetSyncHashUncached(),'10: the digest includes the change (canonical)')
end
check(readyWithoutHash==0,'readiness contract over the whole test: '..readyWithoutHash..' ready report(s) without a digest')

print('PASS dps_sync_digest_bounded: bounded preparation, canonical digest, nothing partial or stale advertised, Sync waits checks='..checks)
