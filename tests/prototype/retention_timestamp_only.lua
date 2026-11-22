-- Timestamp-only retention runs (user-approved 2026-11-20). In the default
-- (unlimited) mode a retention run that removes nothing and would change no
-- saved metadata except nextMaintenanceAt used to save that time through one
-- full catalog publication (every row, its index and witness prepared again).
-- Such a run now writes nothing and keeps the same next-run time (300 s) for
-- this session only; a saved time still in the future is honored. A reload
-- loses the session time, so the next session evaluates once more and again
-- writes nothing. A removal, a marker's first observation, a mode or schema
-- change is saved as before, through the same full publication.
-- Real TOC boot, real catalog and retention owner; synthetic profile; a
-- session's saved data boots the next one (a reload or a later login).
local T=dofile('tests/prototype/startup_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local ROWS,POOL=30,80
local function Clone(v,seen)
 if type(v)~='table' then return v end;seen=seen or {};if seen[v] then return seen[v] end
 local t={};seen[v]=t;for k,c in pairs(v) do t[Clone(k,seen)]=Clone(c,seen) end;return t
end
local function Serialize(v,depth)
 depth=depth or 0
 if type(v)~='table' then return type(v)..':'..tostring(v) end
 assert(depth<12,'serialize depth')
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local out={};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..Serialize(v[k],depth+1) end
 return '{'..table.concat(out,',')..'}'
end
local W -- the current session
local function Session(db,startAt,busyFirst,refuseFirst)
 Nexus=nil;SlashCmdList=nil;ProjectEbonhold=nil;NexusDB=db;WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua');H.now=startAt;T.Load()
 local C,R=Nexus.BuildCatalog,Nexus.DataRetention
 local w={H=H,C=C,R=R,start=startAt,opened=0,busy=0,results={}}
 local begin=C.BeginCatalogMaintenance
 C.BeginCatalogMaintenance=function(req,...)
  if type(req)=='table' and req.operation=='retention' then
   if busyFirst and w.busy<busyFirst then w.busy=w.busy+1;return nil,'ROOT_MUTATION_PENDING' end
   local h,why=begin(req,...)
   if h then w.opened=w.opened+1 end
   return h,why
  end
  return begin(req,...)
 end
 -- A retention commit that publishes (anything but the catalog's immediate
 -- no-op answer, true with applied=0).
 w.published=0;w.refused=0
 local commit=C.CommitMaintenance
 C.CommitMaintenance=function(h,...)
  if refuseFirst and w.refused<refuseFirst and type(h)=='table' and h.operation=='retention' then
   w.refused=w.refused+1;C.CancelMaintenance(h);return false,'SOURCE_DRIFT'
  end
  local r={commit(h,...)}
  if type(h)=='table' and h.operation=='retention'
   and not (r[1]==true and type(r[2])=='table' and r[2].applied==0) then w.published=w.published+1 end
  return unpack(r)
 end
 local enforce=R.Enforce
 R.Enforce=function(...)
  local was=w.opened
  local r={enforce(...)};w.results[#w.results+1]=r[1]
  if w.opened>was then w.lastEval=w.H.now end
  return unpack(r)
 end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H,function() return Nexus.StartupStatus().state=='ready' end)
 w.atReady={stats=Clone(C.DebugStats()),generation=C.Status().generation}
 W=w
 return w
end
local function Settle(w,seconds) w.H.Advance(seconds or 120,.05) end
local function Logout(w) w.H.Fire('PLAYER_LEAVING_WORLD');w.H.Fire('PLAYER_LOGOUT');return Clone(NexusDB),w.H.now end
local function Meta() return (NexusDB.authorityBundle or {}).dataRetention end
local function Delta(w,key) return w.C.DebugStats()[key]-w.atReady.stats[key] end
local function NoWrite(w,tag)
 check(w.published==0,tag..': retention published nothing: '..w.published)
 check(Delta(w,'maintenanceCommits')==0 and Delta(w,'bundleWrites')==0,tag..': no catalog write after ready: commits '
  ..Delta(w,'maintenanceCommits')..' bundle writes '..Delta(w,'bundleWrites'))
 check(Delta(w,'servingSwaps')==0 and w.C.Status().generation==w.atReady.generation,tag..': the serving root is the same')
 check(Delta(w,'rowWalks')==0,tag..': no row is walked again: '..Delta(w,'rowWalks'))
end

-- 1. The first run ever (no saved retention metadata) saves it, as before.
local s1=Session(T.Profile(ROWS,POOL),1000)
Settle(s1)
local m1=Meta()
check(type(m1)=='table' and type(m1.last)=='table' and m1.last.contentUnlimited==true,'1: the first run saves its metadata')
check(tonumber(m1.nextMaintenanceAt) and m1.nextMaintenanceAt>1700000000,'1: with its next-run time')
check(s1.published==1,'1: through one retention publication: '..s1.published)
local saved1,end1=Logout(s1)

-- 2. A later login (the saved time has passed), nothing to remove: the run
-- evaluates and writes nothing; the saved metadata is byte for byte the same.
local before=Serialize(saved1.authorityBundle.dataRetention)
local s2=Session(Clone(saved1),end1+3600)
Settle(s2)
check(s2.opened==1,'2: the start-up run evaluates once: '..s2.opened)
check(Serialize(Meta())==before,'2: the saved retention metadata is unchanged')
check((tonumber(s2.R.NextMaintenanceAt()) or 0)>tonumber(Meta().nextMaintenanceAt),
 '2: the session holds the next-run time, later than the saved one: '..tostring(s2.R.NextMaintenanceAt()))
NoWrite(s2,'2')
local r=s2.results[#s2.results]
check(type(r)=='table' and r.pending==false and r.blocked==nil and r.contentUnlimited==true
 and r.evictionMarkersRemoved==0 and r.tombstonesRemoved==0,'2: the run finished with nothing removed')
-- the same 300 s interval holds in this session
local opened=s2.opened
r=s2.R.Enforce(nil,'test: within the interval')
check(type(r)=='table' and s2.opened==opened,'2: a run within 300 s takes the fast path and opens nothing')
local lastEval=s2.lastEval
s2.H.Advance(lastEval+301-s2.H.now,.05)
r=s2.R.Enforce(nil,'test: after the interval')
-- (a scheduled run may be the one that evaluates at the 300 s mark; then
-- this call is inside its new interval)
check(s2.opened==opened+1 and s2.lastEval>=lastEval+300 and type(r)=='table' and r.pending==false,
 '2: after 300 s one run evaluates again: '..opened..'->'..s2.opened)
check(Serialize(Meta())==before,'2: and again writes nothing')
NoWrite(s2,'2 again')
local saved2,end2=Logout(s2)

-- 3. A reload loses the session time: the next session evaluates once more
-- (the same bounded run) and writes nothing.
local s3=Session(Clone(saved2),end2+60)
Settle(s3)
check(s3.opened==1 and Serialize(Meta())==before,'3: a reload repeats the bounded evaluation and writes nothing')
NoWrite(s3,'3')
Logout(s3)

-- 4. A saved time still in the future is honored: no run is evaluated.
local s4=Session(Clone(saved1),end1+60)
Settle(s4)
check(s4.R.NextMaintenanceAt()==tonumber(Meta().nextMaintenanceAt),'4: the saved time is the next-run time')
check(s4.opened==0 and type(s4.results[1])=='table' and s4.results[1].blocked==nil,'4: a reload within the saved interval takes the fast path: '..s4.opened)
Logout(s4)

-- 5. Real writes still go through: a marker seen for the first time is saved
-- with the run's metadata, and it expires 30 days later through the catalog.
local withMarker=Clone(saved1)
withMarker.authorityBundle.communityRetentionEvictions=withMarker.authorityBundle.communityRetentionEvictions or {}
withMarker.authorityBundle.communityRetentionEvictions['legacy-marker-1']=1600000000
local s5=Session(withMarker,end1+3600)
Settle(s5)
local m5=Meta()
check(type(m5.markerFirstSeen)=='table' and m5.markerFirstSeen['legacy-marker-1']~=nil,'5: the first observation is saved')
check(s5.published==1 and tonumber(m5.nextMaintenanceAt)>tonumber(m1.nextMaintenanceAt),
 '5: through one publication, with its next-run time saved')
local saved5,end5=Logout(s5)
local s6=Session(Clone(saved5),end5+31*86400)
Settle(s6)
local m6=Meta()
check(saved5.authorityBundle.communityRetentionEvictions['legacy-marker-1']~=nil
 and (NexusDB.authorityBundle.communityRetentionEvictions or {})['legacy-marker-1']==nil,'5: 30 days later the marker expires')
check(s6.published==1 and (m6.markerFirstSeen==nil or m6.markerFirstSeen['legacy-marker-1']==nil)
 and m6.last.evictionMarkersRemoved==1 and tonumber(m6.nextMaintenanceAt)>tonumber(m5.nextMaintenanceAt),
 '5: the removal is published with its metadata and next-run time')
Logout(s6)

-- 6. Any other metadata difference takes the full path: a saved metadata
-- without its schema version is saved again with it.
local noSchema=Clone(saved1);noSchema.authorityBundle.dataRetention.schemaVersion=nil
local s7=Session(noSchema,end1+3600)
Settle(s7)
check(s7.published==1 and Meta().schemaVersion==s7.R.SchemaVersion(),'6: a schema difference is saved, as before')
Logout(s7)

-- 7. A run that finds the catalog busy keeps no session time (the start-up
-- run is not retried; that is unchanged): the next request evaluates, writes
-- nothing, and only then holds the interval.
local s8=Session(Clone(saved1),end1+3600,1)
Settle(s8,1)
check(s8.busy==1 and s8.results[1] and s8.results[1].blocked==true and s8.opened==0,'7: the start-up run found the catalog busy')
Settle(s8)
check(s8.opened==0 and Serialize(Meta())==before,'7: nothing evaluated or written meanwhile')
r=s8.R.Enforce(nil,'test: after the busy run')
check(s8.opened==1 and type(r)=='table' and r.pending==false,'7: the next request evaluates (no session time was kept)')
check(Serialize(Meta())==before,'7: and writes nothing')
NoWrite(s8,'7')
r=s8.R.Enforce(nil,'test: after the evaluation')
check(type(r)=='table' and s8.opened==1,'7: then the interval holds')
Logout(s8)

-- 8. A no-op commit the catalog refuses (here SOURCE_DRIFT) keeps no session
-- time either: the next request evaluates again.
local s9=Session(Clone(saved1),end1+3600,nil,1)
Settle(s9,1)
local first=s9.results[1]
check(s9.refused==1 and type(first)=='table' and first.blocked==true and first.reason=='SOURCE_DRIFT','8: the start-up run was refused')
check(Serialize(Meta())==before,'8: nothing was written')
r=s9.R.Enforce(nil,'test: after the refusal')
check(s9.opened==2 and type(r)=='table' and r.pending==false and r.blocked==nil,'8: the next request evaluates: '..s9.opened)
NoWrite(s9,'8')
Logout(s9)

-- 9. The comparison covers saved fields the run would drop, and a saved
-- metadata without any next-run time.
local extra=Clone(saved1);extra.authorityBundle.dataRetention.markerFirstSeen={}
local s10=Session(extra,end1+3600)
Settle(s10)
check(s10.published==1 and Meta().markerFirstSeen==nil,'9: a saved field the run would drop is saved (full path)')
Logout(s10)
local noNext=Clone(saved1);noNext.authorityBundle.dataRetention.nextMaintenanceAt=nil
local beforeNoNext=Serialize(noNext.authorityBundle.dataRetention)
local s11=Session(noNext,end1+3600)
Settle(s11)
check(s11.published==0 and s11.opened==1 and Serialize(Meta())==beforeNoNext,'9: no saved next-run time: still nothing is written')
check(tonumber(s11.R.NextMaintenanceAt()) and s11.R.NextMaintenanceAt()>end1+3600,'9: the next-run time is the session one: '..tostring(s11.R.NextMaintenanceAt()))
Logout(s11)

print('PASS retention timestamp-only runs: '..checks..' checks')
