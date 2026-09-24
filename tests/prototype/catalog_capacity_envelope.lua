-- Capacity envelope V2 (owner decision of 2026-09-24): up to 2048 different
-- build identities across saved and shipped builds together, up to 2048
-- removal markers, up to 2048 retention markers, and so at most 6144
-- different typed identities. A typed ID in several categories is one
-- identity; the number 5 and the string "5" are two. Only the active source
-- is counted: once a saved bundle exists, stale legacy tables are not. Real
-- TOC boot and admission; synthetic data.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local clock=1790000000
local function Clock() time=function() return clock end end
local function Count(t) local n=0;for _ in pairs(t or {})do n=n+1 end;return n end
local function Record(id)
 return {id=id,title='Synthetic '..tostring(id),author='Peer-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}}
end
local ordinary,locked={},{}
for i=1,79 do ordinary[i]={spellId=300000+i,quality=2,stacks=1} end
for i=1,6 do locked[i]={spellId=310000+i,quality=3,stacks=1} end
-- A complete valid build at the supported envelope: 79 ordinary + 6 locked.
local function FullRecord(id,n)
 local echoes,lockedEchoes={},{}
 for i,e in ipairs(ordinary) do echoes[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks} end
 for i,e in ipairs(locked) do lockedEchoes[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks} end
 return {id=id,title='Full build '..id,author='Peer'..(n%29)..'-Realm',class='MAGE',postedAt=1700000000+n,
  lastModified=1700000000+n,description=string.rep('Rotation note. ',20),ordinaryComplete=true,
  loadoutAvailable=true,lockedComplete=true,echoes=echoes,lockedEchoes=lockedEchoes}
end
local function V1Marker(id,at)
 return {schemaVersion=1,typedId={luaType=type(id),exactValue=id},evictedCatalogGeneration=1,
  evictedSourceIdentity='overlay',evictedProvenanceIdentity='',receiptRevision=1,receiptAtServerTime=at}
end
local function Map(fill,from,to) local m={};for i=from,to do fill(m,i) end;return m end
local function Db(builds,tombs,marks)
 return {settingsVersion=5,settings={},chars={},communityBuilds=builds,syncTombstones=tombs,communityRetentionEvictions=marks}
end
local function Boot(db,shipped)
 F.fileHooks=shipped and {[ [[data\BundledBuilds.lua]] ]=function()Nexus.BundledBuilds.builds=shipped end} or nil
 local H=F.Boot(db,Clock);F.fileHooks=nil
 return H,Nexus.BuildCatalog,Nexus.StartupStatus()
end

-- 1. Every category at its own limit, all identities different: 6144.
local builds=Map(function(m,i) m['b-'..i]=Record('b-'..i) end,1,2048)
local tombs=Map(function(m,i) m['t-'..i]={stamp=1700000000+i,author='OldPeer'} end,1,2048)
local marks=Map(function(m,i) m['r-'..i]=V1Marker('r-'..i,clock-3600) end,1,2048)
local H,C,s=Boot(Db(builds,tombs,marks))
local st=C.Status()
check(s.state=='ready' and C.RootState().state=='ROOT_ADMITTED','all three categories at 2048 are admitted: '..tostring(s.reason))
check(st.buildIdentityCount==2048 and st.availableCount==2048 and st.tombstoneCount==2048 and st.barrierCount==2048,
 'counts: '..st.buildIdentityCount..'/'..st.tombstoneCount..'/'..st.barrierCount)
local budget=C.Budget().totals
check(budget.rows==2048 and budget.tombstones==2048 and budget.barriers==2048 and budget.identities==6144
 and budget.rootMapEdges==8192,'the declared limits are 2048/2048/2048, 6144 identities and 8192 raw keys')

-- 2. Only the active source counts: stale legacy tables beside the saved
-- bundle are not added to it.
NexusDB.communityBuilds=Map(function(m,i) m['stale-b-'..i]=Record('stale-b-'..i) end,1,3000)
NexusDB.syncTombstones=Map(function(m,i) m['stale-t-'..i]={stamp=1,author='X'} end,1,3000)
NexusDB.communityRetentionEvictions=Map(function(m,i) m['stale-r-'..i]=1 end,1,3000)
H=F.Boot(NexusDB,Clock);C=Nexus.BuildCatalog;st=C.Status()
check(Nexus.StartupStatus().state=='ready' and st.buildIdentityCount==2048 and st.tombstoneCount==2048
 and st.barrierCount==2048,'with the bundle active, 3000 stale legacy keys per map are not counted')

-- 3. (A 2049th build, removal marker or retention marker is refused on its
-- own map-key counter: catalog_root_capacity and catalog_capacity_local_ready.)

-- 4. Typed identity: saved string IDs and shipped numeric IDs with the same
-- digits are different builds; the same typed ID saved and shipped is one.
local strings=Map(function(m,i) m[tostring(i)]=Record(tostring(i)) end,1,1024)
local numbers=Map(function(m,i) m[i]=Record(i) end,1,1024)
local _,C4,s4=Boot(Db(strings,nil,nil),numbers)
check(s4.state=='ready' and C4.Status().buildIdentityCount==2048,'1024 string + 1024 numeric IDs are 2048 builds')
local numbers1025=Map(function(m,i) m[i]=Record(i) end,1,1025)
local _,_,s5=Boot(Db(Map(function(m,i) m[tostring(i)]=Record(tostring(i)) end,1,1024),nil,nil),numbers1025)
check(s5.state=='failed' and s5.reason=='ROOT_SLOT_LIMIT' and (s5.failure or {}).counter=='distinct-builds',
 'one more typed ID is refused on the distinct-build counter: '..tostring((s5.failure or {}).counter))
-- 200 builds saved and shipped under the same IDs plus 1848 saved-only builds
-- are 2048 builds (2248 raw entries); counting them twice would refuse.
local savedMix=Map(function(m,i) m['same-'..i]=Record('same-'..i) end,1,200)
for i=1,1848 do savedMix['own-'..i]=Record('own-'..i) end
-- Checked at catalog admission: the later start-up identity repair of saved
-- rows beneath shipped rows is a separate, slower route that this count does
-- not depend on.
local function BootUntilAdmitted(db,shipped)
 Nexus=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local HH=dofile('tests/prototype/harness.lua')
 NexusDB=db;Clock()
 F.fileHooks={[ [[data\BundledBuilds.lua]] ]=function()Nexus.BundledBuilds.builds=shipped end}
 for line in io.lines('Nexus.toc')do
  line=line:gsub('\r','')
  if line~='' and not line:match('^#')then
   assert(loadfile((line:gsub('\\','/'))))('Nexus',{})
   if F.fileHooks[line] then F.fileHooks[line]() end
  end
 end
 F.fileHooks=nil
 HH.Fire('ADDON_LOADED','Nexus');HH.Fire('PLAYER_ENTERING_WORLD')
 for _=1,20000 do
  HH.Advance(.05,.05)
  local root=Nexus.BuildCatalog.RootState()
  if root.state=='ROOT_ADMITTED' or root.state=='ROOT_INVALIDATED' then break end
 end
 return Nexus.BuildCatalog
end
local C6=BootUntilAdmitted(Db(savedMix,nil,nil),Map(function(m,i) m['same-'..i]=Record('same-'..i) end,1,200))
check(C6.RootState().state=='ROOT_ADMITTED' and C6.Status().buildIdentityCount==2048,
 'saved and shipped copies of one ID are one build: '..tostring(C6.RootState().state)..' '..tostring(C6.Status().buildIdentityCount))

-- 5. Overlap across categories: a removal marker and a retention marker on
-- the same ID are one identity; removal markers on saved builds keep those
-- builds as identities (not available).
local d7=Db(Map(function(m,i) m['x-'..i]=Record('x-'..i) end,1,2048),
 Map(function(m,i) m['x-'..i]={stamp=1,author='X'} end,1,2048),
 Map(function(m,i) m['y-'..i]=V1Marker('y-'..i,clock) end,1,2048))
for i=1,2048 do d7.syncTombstones['y-'..i]=nil end
for i=1,1024 do d7.syncTombstones['y-'..i]={stamp=1,author='X'};d7.syncTombstones['x-'..(1024+i)]=nil end
local _,C7,s7=Boot(d7)
local st7=C7.Status()
check(s7.state=='ready' and st7.buildIdentityCount==2048 and st7.tombstoneCount==2048 and st7.barrierCount==2048,
 'overlapping categories are admitted and counted per category: '..tostring(s7.reason))
check(st7.availableCount==1024,'builds under a removal marker are not available; the others are: '..st7.availableCount)

-- 6. Full-size valid builds (79 ordinary + 6 locked copies) beside both
-- marker maps at their limits: admitted, every copy kept exactly.
local full=Map(function(m,i) m['full-'..i]=FullRecord('full-'..i,i) end,1,256)
local _,C8,s8=Boot(Db(full,Map(function(m,i) m['t-'..i]={stamp=1,author='X'} end,1,2048),
 Map(function(m,i) m['r-'..i]=V1Marker('r-'..i,clock) end,1,2048)))
check(s8.state=='ready' and C8.Status().availableCount==256,'256 full-size builds beside 4096 markers are admitted')
local sample=C8.Get('full-17')
local ordinaryCopies,lockedCopies=0,0
for _,e in ipairs(sample and sample.echoes or {}) do ordinaryCopies=ordinaryCopies+(e.stacks or 1) end
for _,e in ipairs(sample and sample.lockedEchoes or {}) do lockedCopies=lockedCopies+(e.stacks or 1) end
check(ordinaryCopies==79 and lockedCopies==6,'a full build keeps exactly 79 ordinary and 6 locked copies: '..ordinaryCopies..'/'..lockedCopies)
local budgetCounters=C8.BudgetCounters()
local m=budgetCounters.maxPerPump or {}
check((m.rows or 0)<=8 and (m.rootMapEdges or 0)<=64 and (m.edges or 0)<=64 and (m.nodes or 0)<=64,
 'the per-pump slices are unchanged')
print('PASS catalog_capacity_envelope: 2048/2048/2048 admitted, stale legacy not counted, typed and shared identities, category overlap, full-size builds beside full marker maps checks='..checks)
