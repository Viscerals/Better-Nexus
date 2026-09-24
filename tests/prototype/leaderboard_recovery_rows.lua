-- Leaderboard rows from saved data, through the real start-up and the real
-- view. Synthetic players and builds only; no player data.
--
-- Saved Community builds, DPS character-best rows, removal markers and
-- retention markers are written in the legacy saved locations
-- (leaderboard_fixture_support.lua). The real TOC boot admits them and moves
-- them into the authority bundle; the Leaderboard is opened with
-- Nexus.Leaderboard.Show and read from its rendered rows and detail pane.
-- Nothing is injected into the view, no readiness flag is set and no
-- production function is replaced.
--
-- Current code: builds and marker-only IDs share one 2048-key catalog budget,
-- so this fixture stays small. The sizes below are parameters; a caller may
-- set the global LEADERBOARD_RECOVERY_SIZE before dofile to compose a larger
-- catalog (keyBudget is the envelope the code under test admits) or to use
-- the current exact marker shapes (markerShape='v1'; default 'legacy', the
-- shapes an older retention owner wrote). minDistinctKeys asserts a lower
-- bound on the identities the saved data holds (e.g. above the old shared
-- 2048). expireAfterDays enables section 3b: the retention-marker expiry
-- step, with the harness clock moved forward that many days before a real
-- start-up.
-- settleSeconds bounds the wait for post-start-up background work: about
-- 3 s here; about 2300 simulated seconds at 2000 builds on the first
-- start-up (scheduler-paced evidence compaction, then the build hash
-- warm-up), and only while no Community Builds projection runs (it shares
-- the catalog's single "summary" cursor with the hash warm-up).
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local started=os.clock()

local SIZE={extraBuilds=6,removalMarkers=5,retentionMarkers=5,keyBudget=2048,settleSeconds=120,markerShape='legacy',
 minDistinctKeys=0,expireAfterDays=nil}
for k,v in pairs(rawget(_G,'LEADERBOARD_RECOVERY_SIZE') or {})do SIZE[k]=v end
local S=L.STAMP
local fx=L.New({extraBuilds=SIZE.extraBuilds,removalMarkers=SIZE.removalMarkers,
 retentionMarkers=SIZE.retentionMarkers,markerShape=SIZE.markerShape,players={
 {name='Alpha',class='MAGE',dps={lk=52000,dummy=48000}},
 {name='Bravo',class='PRIEST',dps={lk=61000,dummy=65000}},
 -- Same Lich King DPS as Alpha, earlier record: ranked first of the two.
 {name='Charlie',class='WARRIOR',dps={lk=52000},ts={lk=S+50}},
 -- Dummy only, no locked Echo.
 {name='Delta',class='ROGUE',dps={dummy=70000},locked=0},
 -- One Echo held as an ordinary copy and as a locked copy.
 {name='Echo',class='DRUID',dps={lk=40000,dummy=41000},sharedLocked=true},
 -- DPS rows whose build is not a build: never received, removed, evicted.
 {name='Foxtrot',class='HUNTER',dps={lk=45000,dummy=30000},build='missing'},
 {name='Golf',class='SHAMAN',dps={lk=44000,dummy=31000},build='tombstone'},
 {name='Hotel',class='WARLOCK',dps={lk=43000},build='retention'},
 -- The harness character's own build and records.
 {name='PrototypeTester',class='MAGE',dps={lk=39000,dummy=38000},isLocal=true},
 -- A saved build with no record yet; section 3 receives one for it.
 {name='Kilo',class='PALADIN'},
}})
check(fx:DistinctKeys()<=SIZE.keyBudget,'fixture: builds and marker-only IDs fit the '..SIZE.keyBudget..'-key budget: '..fx:DistinctKeys())
check(fx:DistinctKeys()>=SIZE.minDistinctKeys,'fixture: the saved data holds at least '..SIZE.minDistinctKeys..' identities: '..fx:DistinctKeys())
local removalCount,retentionCount=L.Count(fx.removal),L.Count(fx.retention)
-- Set by section 3b once the retention markers have expired.
local retentionExpired=false
-- Catalog records the test expects: the fixture builds, plus any record the
-- product itself adds during the test (asserted where it is added).
local known,mirrors={},{}
for _,id in ipairs(fx.buildOrder)do known[id]=true end

-- The local plan comes from format5_support (character row 'Gen plan',
-- assigned to server slot 1). The harness shows the same slot as active.
local function ServerSlots(H)
 H.perks.serverBuildSlots={[1]={name='Gen plan',verified=true,echoes=L.Copy(F.PLAN)}}
 H.perks.serverActiveSlot=1
end
local planKey=F.Key(F.PLAN)

-- The harness clock. time() and GetServerTime() are the simulated client
-- APIs from harness.lua (1700000000 + H.now, H.now starting at 1000 in every
-- boot). With expireAfterDays set, the test installs the same clock plus a
-- test-controlled offset before each boot, so the retention owner records
-- first observations at a known time and a later session can start that many
-- days later. The clock never steps backward inside one session. Between
-- sessions without an offset it restarts lower (H.now restarts at 1000), so
-- CLOCK.latest keeps the latest time any session has read.
local CLOCK={base=1700000000,offset=0,latest=0}
local function Before(H)
 ServerSlots(H)
 if SIZE.expireAfterDays then
  time=function()
   local t=CLOCK.base+CLOCK.offset+math.floor(H.now)
   if t>CLOCK.latest then CLOCK.latest=t end
   return t
  end
  GetServerTime=time
 end
end

local function List(rows,field)
 local out={}
 for _,r in ipairs(rows or {})do out[#out+1]=tostring(r.spellId)..':'..tostring(r[field or 'count'] or r.stacks or r.count) end
 return table.concat(out,',')
end
local function Stacks(rows)return List(rows,'stacks')end
local function Spells(rows)
 local out={};for _,r in ipairs(rows or {})do out[#out+1]=tostring(r.spellId) end;return table.concat(out,',')
end
local LABEL={lk='Lich King',dummy='Training Dummy',combined='Both records'}

-- Start-up is followed by background catalog work (evidence compaction, the
-- build hash warm-up, a scheduled retention run), during which the Sync gate
-- reports catalog-not-ready or hashes-not-ready. Advance until that work is
-- observed to be finished: gate open, no catalog candidate, no compaction
-- pump and no retention run scheduled, held for two seconds. Bounded;
-- nothing is forced. (A record received while compaction is still walking
-- its evidence pool is lost at the compaction commit - reported separately -
-- so section 3 receives its record only after this settles.)
local function Settle(H)
 local quiet=0
 for _=1,math.floor(SIZE.settleSeconds*20) do
  H.Advance(.05,.05)
  local s=Nexus.StartupStatus()
  -- A refused start-up never settles; the caller reports its facts.
  if s.state=='failed' then return s end
  local calm=s.syncGate=='open' and not Nexus.BuildCatalog.RootState().candidate
   and not Nexus.Scheduler.Pending('data-compaction')
   and not Nexus.Scheduler.Pending('data-retention.enforce')
  quiet=calm and quiet+1 or 0
  if quiet>=40 then return s end
 end
 local s=Nexus.StartupStatus()
 error('background start-up work did not settle within '..SIZE.settleSeconds..' s: gate '..tostring(s.syncGate))
end

-- Start-up facts must agree with what the shared views and Sync then do.
local function Readiness(tag,H)
 local s=Settle(H)
 local f=s.failure or {}
 check(s.coreReady==true and s.state=='ready' and not s.reason,tag..': start-up is ready with no failure: '..tostring(s.state)..' '..tostring(s.reason)
  ..(s.reason and (' (map '..tostring(f.map)..', counter '..tostring(f.counter)..', count '..tostring(f.count)..', limit '..tostring(f.limit)..')') or ''))
 check(s.syncReady==true and s.dpsReady==true,tag..': Sync and DPS report ready')
 check(s.syncGate=='open' and s.syncGateAdapterReady and s.syncGateCatalogReady and s.syncGateHashesReady,
  tag..': the Sync gate is open with adapter, catalog and hashes ready: '..tostring(s.syncGate))
 check(Nexus.LoadingStatus.CapacityText(s)==nil,tag..': no capacity refusal sentence')
 local C=Nexus.BuildCatalog
 check(C.RootState().state=='ROOT_ADMITTED',tag..': the shared catalog is admitted')
 local st=C.Status()
 local other={}
 for id,b in pairs(NexusDB.authorityBundle.communityBuilds)do
  if not known[id] then other[#other+1]=tostring(id)..(type(b)=='table' and b.importedSavedBuild and ' (saved loadout)' or '') end
 end
 table.sort(other)
 check(st.availableCount==L.Count(known) and st.overlayCount==L.Count(known) and st.invalidCount==0,
  tag..': every expected build is available and none is invalid: '..st.availableCount..'/'..st.overlayCount..'/'..st.invalidCount
  ..'; records that are not fixture builds: '..table.concat(other,', '))
 local liveRetention=retentionExpired and 0 or retentionCount
 check(st.tombstoneCount==removalCount and st.barrierCount==liveRetention,
  tag..': the catalog holds the removal and retention markers: '..st.tombstoneCount..'/'..st.barrierCount)
 if st.buildIdentityLimit~=nil then
  -- Capacity envelope V2 facts, where the code under test reports them.
  check(st.buildIdentityCount==L.Count(known) and st.buildIdentityLimit==2048
   and st.tombstoneLimit==2048 and st.barrierLimit==2048,
   tag..': capacity facts: '..tostring(st.buildIdentityCount)..' build identities of '..tostring(st.buildIdentityLimit))
  check(C.SaturationSummary()==nil,tag..': no capacity refusal was recorded')
 end
 return s
end

-- Build IDs listed by the real Community projection (all pages, no class or
-- qualification filter). Scope 'all' lists the ordinary builds; scope 'mine'
-- lists the local character's own builds and saved-loadout mirrors.
local function CommunityCheck(tag,H)
 local all=L.CommunityIds(H,'all')
 check(L.Count(all)==#fx.buildOrder,tag..': Community (all) lists exactly the fixture builds: '..L.Count(all))
 for _,id in ipairs(fx.buildOrder)do check(all[id],tag..': Community (all) lists '..id) end
 local mine=L.CommunityIds(H,'mine')
 local own={}
 for _,p in ipairs(fx.players)do if p.isLocal and p.build=='present' then own[p.buildId]=true end end
 for id in pairs(mirrors)do own[id]=true end
 check(L.Count(mine)==L.Count(own),tag..': Community (mine) lists exactly the local character\'s builds: '..L.Count(mine))
 for id in pairs(own)do check(mine[id],tag..': Community (mine) lists '..id) end
 for _,id in ipairs(fx.markerOrder)do check(not all[id] and not mine[id],tag..': Community does not list marker-only '..id) end
end

-- Marker-only IDs stay markers: no build, no summary, blocked reservation.
local function MarkerCheck(tag)
 local C=Nexus.BuildCatalog
 for _,id in ipairs(fx.markerOrder)do
  local kind=fx.markerIds[id]
  check(C.Get(id)==nil and C.GetSummary(id)==nil and not C.IsAdmittedRecord(id),tag..': '..id..' is not a build')
  if kind=='retention' and retentionExpired then
   check(C.BarrierState(id).blocked==false and C.AuthorityState(id).occupancy=='VACANT',
    tag..': expired retention marker '..id..' leaves a vacant ID: '..tostring(C.AuthorityState(id).occupancy))
  else
   check(C.AuthorityState(id).occupancy=='BLOCKED',tag..': '..id..' stays a blocked reservation')
  end
  if kind=='removal' then
   check(C.TombstoneState(id).state~='NONE',tag..': '..id..' is read as a removal marker: '..tostring(C.TombstoneState(id).state))
  elseif not retentionExpired then
   check(C.BarrierState(id).blocked==true,tag..': '..id..' is read as a retention marker: '..tostring(C.BarrierState(id).state))
  end
 end
 local b=NexusDB.authorityBundle
 for id in pairs(fx.removal)do check(b.syncTombstones[id]~=nil,tag..': saved removal marker '..id..' is kept') end
 for id in pairs(fx.retention)do
  if retentionExpired then
   check(b.communityRetentionEvictions[id]==nil,tag..': expired retention marker '..id..' is removed from the saved map')
  else
   check(b.communityRetentionEvictions[id]~=nil,tag..': saved retention marker '..id..' is kept')
  end
 end
end

-- Saved scores in the durable DPS store equal the fixture's.
local function SavedScores(tag)
 local best=NexusDB.authorityBundle.dpsCapture.characterBest
 for _,p in ipairs(fx.players)do
  for _,category in ipairs({'lk','dummy'})do
   local row=best[category][p.owner]
   if p.dps[category] then
    check(row and row.dps==p.dps[category] and row.ts==p.ts[category] and row.buildId==p.buildId
     and row.fingerprint==p.fingerprint and row.ownerVerified==true,
     tag..': saved '..category..' score of '..p.owner..' is kept: '..tostring(row and row.dps))
   else
    check(row==nil,tag..': no '..category..' row appears for '..p.owner)
   end
  end
 end
end

-- One rendered row and its detail pane, checked against the fixture.
local function RowCheck(tag,category,i,r,e,H)
 local p,d=e.player,r.data
 local label=tag..' '..category..' #'..i..' '..p.name
 check(r.rank==i,label..': rank text shows the position')
 check(d.ownerKey==p.owner and Nexus.Identity.VerifiedOwnerKey(d)==p.owner,label..': the row belongs to '..p.owner..': '..tostring(d.ownerKey))
 check(r.player==p.displayPlayer and d.player==p.name,label..': the player is shown as '..p.displayPlayer..': '..tostring(r.player))
 check(d.dps==e.dps and r.dps:find(string.format('%.1fk DPS',e.dps/1000),1,true),label..': DPS '..e.dps..': '..tostring(r.dps))
 check(d.resolvedClass==p.class,label..': class '..p.class..': '..tostring(d.resolvedClass))
 check(d.fingerprint==p.fingerprint and List(d.echoes,'stacks')==List(p.dpsOrdinary),label..': the exact ordinary evidence')
 check(d.lockedFingerprint==p.lockedFingerprint,label..': the locked fingerprint '..p.lockedFingerprint..': '..tostring(d.lockedFingerprint))
 local hasLocked=#p.locked>0
 check(d.lockedEvidenceStatus==(hasLocked and 'ok' or 'none'),label..': locked evidence status: '..tostring(d.lockedEvidenceStatus))
 if hasLocked then check(List(d.lockedEchoes,'stacks')==List(p.dpsLocked),label..': the exact locked evidence') end
 if category=='combined' then
  check(d.dummyDps==p.dps.dummy and d.lkDps==p.dps.lk and d.average==e.average,label..': both records and their average')
  check(d.dummyEvidence.ownerKey==p.owner and d.lkEvidence.ownerKey==p.owner,label..': both records belong to the owner')
  check(r.extra:find('Dummy',1,true) and r.extra:find('LK',1,true),label..': the both-records line is shown')
 else
  check(d.ts==p.ts[category] and d.duration==p.duration[category] and d.level==p.level,label..': record time, duration and level')
 end
 local det=L.Select(H,i)
 check(det.row and det.row.ownerKey==p.owner,label..': selecting the row shows its detail')
 check(det.owner=='by '..p.displayPlayer,label..': detail owner line: '..tostring(det.owner))
 check(List(det.ordinary)==List(p.dpsOrdinary),label..': detail shows the exact ordinary Echoes and copies')
 check(Spells(det.locked)==Spells(p.dpsLocked) and det.lockedTitle==hasLocked,label..': detail shows the exact locked Echoes: '..Spells(det.locked))
 if p.build=='present' then
  check(d.buildId==p.buildId and r.build==p.title and det.title==p.title,label..': the row names build '..p.buildId..': '..tostring(d.buildId))
  check(det.openBuildId==p.buildId and det.openEnabled,label..': Open Build opens '..p.buildId..': '..tostring(det.openBuildId))
  if hasLocked then
   local validated,why=Nexus.CandidateEvidence.Validate(det.copyCandidate)
   check(validated and det.copyEnabled,label..': Copy is available: '..tostring(det.copyReason or why))
   check(validated and Stacks(validated.ordinaryEchoes)==Stacks(p.ordinary)
    and Stacks(validated.lockedEchoes)==Stacks(p.locked),label..': Copy carries the exact ordinary and locked copies')
  end
 else
  -- Product behaviour (ui/Leaderboard.lua ResolveOpenBuildId, CopyEvidence;
  -- DpsCapture DpsBoardEntry): a record whose build is not a build stays
  -- ranked with its saved DPS and inline evidence, has no build identity, and
  -- refuses Open and Copy with these reasons.
  check(d.buildId==nil and d.resolvedBuildId==nil and r.build=='Recorded build' and det.title=='Recorded build',
   label..': the row has no build identity and shows "Recorded build"')
  check(det.openBuildId==nil and det.openReason=='exact build identity is unavailable' and not det.openEnabled,
   label..': Open is refused: '..tostring(det.openReason))
  check(det.copyCandidate==nil and det.copyReason=='exact current build identity is unavailable' and not det.copyEnabled,
   label..': Copy is refused: '..tostring(det.copyReason))
 end
 for id in pairs(fx.markerIds)do
  check(d.buildId~=id and d.resolvedBuildId~=id and det.openBuildId~=id,label..': marker-only '..id..' is not its build')
 end
 local sig={r.player,r.dps,r.build,r.extra,tostring(d.ownerKey),tostring(d.buildId),tostring(d.dps),tostring(d.ts),
  tostring(d.duration),tostring(d.resolvedClass),tostring(d.fingerprint),tostring(d.lockedFingerprint),
  tostring(d.lockedEvidenceStatus),List(d.echoes,'stacks'),List(d.lockedEchoes,'stacks'),tostring(det.title),
  tostring(det.owner),tostring(det.record),tostring(det.more),tostring(det.openBuildId),tostring(det.openReason),
  tostring(det.copyReason),List(det.ordinary),Spells(det.locked)}
 return table.concat(sig,' | ')
end

local function Board(tag,H)
 local out={}
 for _,category in ipairs({'lk','dummy','combined'})do
  L.Open(H,category)
  local v,diag=Nexus.Leaderboard.VirtualStats(),Nexus.Leaderboard.DiagnosticSnapshot()
  local expected=fx:Expected(category)
  check(Nexus.Leaderboard.IsShown() and NexusLeaderboardFrame:IsShown(),tag..' '..category..': the Leaderboard window is open')
  check(v.dataReady and v.lastDataError==nil and v.publishedRows==#expected,
   tag..' '..category..': '..#expected..' rows are published: '..tostring(v.publishedRows))
  check(diag.blockedReason=='none' and diag.projectionCurrent and diag.filterCategory==category
   and diag.catalogCount==L.Count(known),tag..' '..category..': the view reports a current projection over the catalog')
  local rows,total=L.RenderedRows(H)
  check(total==#expected,tag..' '..category..': rendered row count '..total)
  local countLine
  for _,region in ipairs(NexusLeaderboardFrame.regions)do
   local text=region.GetText and region:GetText()
   if type(text)=='string' and text:find(' ranked ',1,true) then countLine=text end
  end
  check(countLine and countLine:find(#expected..' ranked '..LABEL[category],1,true),tag..' '..category..': count line: '..tostring(countLine))
  out[category]={}
  for i,e in ipairs(expected)do
   local r=rows[i]
   check(r~=nil,tag..' '..category..': row '..i..' is rendered')
   if i>1 then check(rows[i-1].data.dps>=r.data.dps,tag..' '..category..': rows are ordered by DPS at '..i) end
   out[category][e.player.owner]=RowCheck(tag,category,i,r,e,H)
  end
 end
 return out
end

local function LocalPlan(tag)
 local state=Nexus.Store.State()
 local plan=state.loadoutWishlists and state.loadoutWishlists[1]
 check(plan and plan.name=='Gen plan' and plan.key==planKey and Stacks(plan.echoes)==Stacks(F.PLAN),
  tag..': the local Wishlist plan and its slot assignment are kept')
 check(state.lockDesignTargetsBySlot and state.lockDesignTargetsBySlot[planKey]
  and state.lockDesignTargetsBySlot[planKey][F.PERMANENT]==true,tag..': the plan\'s locked target is kept')
 check(state.recordedPicks and state.recordedPicks[200001]==1,tag..': recorded picks are kept')
 local A=Nexus.GameAdapter
 A.Poll()
 local assigned=A.AssignedWishlist()
 check(assigned.state=='ready' and assigned.name=='Gen plan' and assigned.key==planKey,
  tag..': the assignment resolves to the saved plan: '..tostring(assigned.state)..' '..tostring(assigned.name))
end

local function SyncNow(tag,H)
 local sent=#H.sent
 local ok,why=Nexus.Sync.RequestSync()
 H.Advance(3,.05)
 check(ok==true,tag..': Sync Now is accepted, as the ready facts say: '..tostring(ok)..' '..tostring(why))
 check(#H.sent>sent,tag..': a Sync request is sent')
end

------------------------------------------------------------------------
-- 1. First start-up from the legacy saved locations.
------------------------------------------------------------------------
local db=fx:Install(F.Database())
local H=F.Boot(db,Before)
Readiness('start-up',H)
check(type(NexusDB.authorityBundle)=='table','start-up: the saved data now lives in the authority bundle')
MarkerCheck('start-up')
SavedScores('start-up')
for _,p in ipairs(fx.players)do
 if p.build~='present' then
  check(Nexus.BuildCatalog.Get(p.buildId)==nil,'start-up: no build is created for '..p.buildId)
 end
end
local first=Board('start-up',H)
CommunityCheck('start-up',H)
LocalPlan('start-up')

-- Open Build hands the selected row to Community Builds.
L.Open(H,'lk')
local rows=L.RenderedRows(H)
local openIndex
for i,r in ipairs(rows)do if r.data.buildId=='lbfx-b-2' then openIndex=i end end
local det=L.Select(H,openIndex)
det.openButton:Click();H.Advance(1,.05)
local selected=Nexus.CommunityBuilds.GetSelectedBuildForPanel()
check(not Nexus.Leaderboard.IsShown() and Nexus.CommunityBuilds.IsShown(),'Open Build: Community Builds replaces the Leaderboard')
check(selected and selected.id=='lbfx-b-2' and selected.ownerKey=='bravo@'..fx.realmKey,'Open Build: the selected build is Bravo\'s build: '..tostring(selected and selected.id))
Nexus.CommunityBuilds.Hide()
-- Product behaviour: opening Community Builds mirrors the local character's
-- active server loadout (harness slot 1, 'Gen plan') as a saved-loadout
-- record. It is the character's own record, not a fixture ID and not a
-- marker ID; from here on it is part of the expected catalog. Its catalog
-- commit is asynchronous, so wait for background work to settle first.
Settle(H)
local added={}
for id in pairs(NexusDB.authorityBundle.communityBuilds)do if not known[id] then added[#added+1]=id end end
check(#added==1,'Open Build: exactly one record is added, the saved-loadout mirror: '..table.concat(added,', '))
local mirror=added[1] and Nexus.BuildCatalog.Get(added[1])
check(mirror and mirror.importedSavedBuild==true and mirror.ownerKey==F.OWNER and mirror.title=='Gen plan',
 'Open Build: the added record is the local character\'s saved loadout: '..tostring(added[1]))
check(added[1]~=nil and not fx.markerIds[added[1]],'Open Build: the mirror does not reuse a marker-only ID')
known[added[1]]=true;mirrors[added[1]]=true
CommunityCheck('after Open Build',H)
SyncNow('start-up',H)

------------------------------------------------------------------------
-- 2. Offline module reload of the saved bundle.
------------------------------------------------------------------------
local scoresBefore=F.Serialize(NexusDB.authorityBundle.dpsCapture.characterBest)
-- F.Reload itself for this size; a chunked literal round trip only when the
-- saved table is too large for one literal (see L.Reload).
H=L.Reload(F,Before)
check(L.lastReloadPieces==nil or SIZE.extraBuilds>100,'reload: format5_support F.Reload is used at the default size')
Readiness('reload',H)
check(F.Serialize(NexusDB.authorityBundle.dpsCapture.characterBest)==scoresBefore,'reload: the saved DPS store is unchanged')
MarkerCheck('reload')
SavedScores('reload')
local second=Board('reload',H)
for _,category in ipairs({'lk','dummy','combined'})do
 for owner,sig in pairs(first[category])do
  check(second[category][owner]==sig,'reload '..category..': '..owner..' renders the same row and detail')
 end
 check(L.Count(second[category])==L.Count(first[category]),'reload '..category..': the same number of rows')
end
CommunityCheck('reload',H)
LocalPlan('reload')
SyncNow('reload',H)

------------------------------------------------------------------------
-- 3. A received record and the retention run over the saved markers.
-- Kilo's first record arrives through the real inbound function, links to
-- Kilo's saved build and requests a retention run (DataRetention.Request,
-- 3 s delay). Which run the retention summary then records depends on the
-- code under test (on 640d71f a run that met another catalog maintenance was
-- dropped; the recovery retries it); this is not asserted. Whichever run is
-- recorded, it must have removed nothing (every marker is younger than 30
-- days), and every marker, build and saved score must still be there.
------------------------------------------------------------------------
local accepted,refusal=fx:Receive('Kilo','lk',{dps=47000,ts=S+200,duration=100})
check(accepted==true,'retention run: Kilo\'s record is accepted: '..tostring(refusal))
check(Nexus.Scheduler.Pending('data-retention.enforce'),'retention run: the record requests a retention run')
for _=1,math.floor(SIZE.settleSeconds*20) do
 H.Advance(.05,.05)
 if not Nexus.Scheduler.Pending('data-retention.enforce') then break end
end
check(not Nexus.Scheduler.Pending('data-retention.enforce'),'retention run: the requested run has been served')
Settle(H)
local stats=Nexus.DataRetention.Stats(NexusDB)
check(type(stats)=='table' and stats.contentUnlimited==true,'retention run: a retention run completed in content-unlimited mode: '..tostring(stats and stats.reason))
check(stats.evictionMarkersRemoved==0 and stats.tombstonesRemoved==0 and stats.overlayRemoved==0
 and stats.characterBestRemoved==0,'retention run: it removes no marker, build or record: '
 ..tostring(stats.evictionMarkersRemoved)..'/'..tostring(stats.tombstonesRemoved)..'/'..tostring(stats.overlayRemoved))
Readiness('retention run',H)
MarkerCheck('retention run')
SavedScores('retention run')
local third=Board('retention run',H)
for _,category in ipairs({'lk','dummy','combined'})do
 for owner,sig in pairs(first[category])do
  check(third[category][owner]==sig,'retention run '..category..': '..owner..' renders the same row and detail')
 end
 local extra=category=='lk' and 1 or 0
 check(L.Count(third[category])==L.Count(first[category])+extra,'retention run '..category..': rows before plus Kilo\'s new record')
end
check(third.lk['kilo@'..fx.realmKey]~=nil,'retention run: Kilo\'s received record is ranked on its saved build')

------------------------------------------------------------------------
-- 3b. Optional (SIZE.expireAfterDays): the 30-day retention-marker expiry.
-- The retention owner records the first local observation of every
-- retention marker without its own local age (older numeric and untimed
-- markers) in authorityBundle.dataRetention.markerFirstSeen. The harness
-- clock then moves 29 days forward for one real start-up (nothing may
-- expire, and no first observation may be reset), then expireAfterDays
-- forward for another. The retention run requested after the shared catalog
-- is ready must then expire every retention marker and change nothing else:
-- removal markers, builds, saved scores, rendered rows, order, owners,
-- build identities and evidence stay exactly as they were, and the evicted
-- build of the retention-marker player is not restored.
------------------------------------------------------------------------
if SIZE.expireAfterDays then
 local C,R=Nexus.BuildCatalog,Nexus.DataRetention
 local ageing=0
 for _,v in pairs(fx.retention)do
  if type(v)=='number' or (type(v)=='table' and v.receiptAtServerTime==0) then ageing=ageing+1 end
 end
 for _=1,math.floor(SIZE.settleSeconds*20) do
  if R.MarkerFirstSeenCount(NexusDB)==ageing then break end
  H.Advance(.05,.05)
 end
 check(R.MarkerFirstSeenCount(NexusDB)==ageing,'expiry: a first observation is recorded for every retention marker without its own age: '
  ..R.MarkerFirstSeenCount(NexusDB)..'/'..ageing)
 local firstSeen=NexusDB.authorityBundle.dataRetention.markerFirstSeen or {}
 local earliest,latest=math.huge,0
 for id,seen in pairs(firstSeen)do
  check(fx.retention[id]~=nil,'expiry: first observations name only retention markers: '..tostring(id))
  earliest,latest=math.min(earliest,seen),math.max(latest,seen)
 end
 -- Recorded from the harness clock, not from the marker values: no earlier
 -- than a session start and no later than the latest time a session read.
 -- They can come from an earlier session of this run (the request made when
 -- the shared catalog is ready is retried while the catalog is busy).
 local now=time()
 check(ageing==0 or (earliest>=CLOCK.base+1000 and latest<=CLOCK.latest),
  'expiry: first observations carry the harness clock of this run: '..tostring(earliest)..'..'..tostring(latest)
  ..' latest harness time '..CLOCK.latest..' now '..now)
 check(C.Status().barrierCount==retentionCount,'expiry: no retention marker expires before 30 days')
 local tombstonesBefore=F.Serialize(NexusDB.authorityBundle.syncTombstones)
 local buildsBefore=F.Serialize(NexusDB.authorityBundle.communityBuilds)
 local scoresNow=F.Serialize(NexusDB.authorityBundle.dpsCapture.characterBest)
 local newest=latest
 for _,v in pairs(fx.retention)do
  if type(v)=='table' and (tonumber(v.receiptAtServerTime) or 0)>newest then newest=v.receiptAtServerTime end
 end

 -- Day 29: a real start-up and its retention run must expire nothing, and
 -- must keep every recorded first observation as it was.
 local firstSeenBefore=F.Serialize(firstSeen)
 CLOCK.offset=29*86400
 H=L.Reload(F,Before)
 C,R=Nexus.BuildCatalog,Nexus.DataRetention
 Settle(H)
 local meta=NexusDB.authorityBundle.dataRetention or {}
 check((tonumber(meta.nextMaintenanceAt) or 0)>CLOCK.base+CLOCK.offset,'day 29: a retention run ran in this session: '..tostring(meta.nextMaintenanceAt))
 check(C.Status().barrierCount==retentionCount and R.MarkerFirstSeenCount(NexusDB)==ageing,
  'day 29: no retention marker expires: '..C.Status().barrierCount..'/'..retentionCount)
 check(F.Serialize(meta.markerFirstSeen or {})==firstSeenBefore,'day 29: the first observations are not reset by a reload or a run')

 CLOCK.offset=SIZE.expireAfterDays*86400
 H=L.Reload(F,Before)
 -- A reload is a new module set: read the new catalog and retention owners.
 C,R=Nexus.BuildCatalog,Nexus.DataRetention
 check(time()-newest>=30*86400,'expiry: the new session starts more than 30 days after every marker age: '..(time()-newest))
 for _=1,math.floor(SIZE.settleSeconds*20) do
  H.Advance(.05,.05)
  if C.Status().barrierCount==0 and not Nexus.Scheduler.Pending('data-retention.enforce') then break end
 end
 retentionExpired=true
 local run=R.Stats(NexusDB)
 check(type(run)=='table' and run.evictionMarkersRemoved==retentionCount and run.tombstonesRemoved==0
  and run.overlayRemoved==0 and run.characterBestRemoved==0,
  'expiry: the retention run expires every retention marker and removes nothing else: '
  ..tostring(run and run.evictionMarkersRemoved)..'/'..tostring(run and run.tombstonesRemoved)..'/'..tostring(run and run.overlayRemoved))
 check(R.MarkerFirstSeenCount(NexusDB)==0,'expiry: the first observations leave with their markers')
 local tag='after '..SIZE.expireAfterDays..' days'
 Readiness(tag,H)
 check(F.Serialize(NexusDB.authorityBundle.syncTombstones)==tombstonesBefore,'expiry: the removal markers are unchanged')
 check(F.Serialize(NexusDB.authorityBundle.communityBuilds)==buildsBefore,'expiry: every saved build is unchanged')
 check(F.Serialize(NexusDB.authorityBundle.dpsCapture.characterBest)==scoresNow,'expiry: the saved scores are unchanged')
 MarkerCheck(tag)
 SavedScores(tag)
 for _,p in ipairs(fx.players)do
  if p.build=='retention' then
   check(C.Get(p.buildId)==nil and not C.IsAdmittedRecord(p.buildId) and C.AuthorityState(p.buildId).occupancy=='VACANT',
    'expiry: '..p.name..'\'s evicted build is not restored')
  end
 end
 local fourth=Board(tag,H)
 for _,category in ipairs({'lk','dummy','combined'})do
  for owner,sig in pairs(third[category])do
   check(fourth[category][owner]==sig,'expiry '..category..': '..owner..' renders the same row and detail')
  end
  check(L.Count(fourth[category])==L.Count(third[category]),'expiry '..category..': the same number of rows')
 end
 CommunityCheck(tag,H)
 LocalPlan(tag)
 SyncNow(tag,H)
end

------------------------------------------------------------------------
-- 4. Cross-check: the same remote builds and records fed through the real
-- inbound functions (BuildCatalog.Put source=remote, DpsCapture.ReceiveRecord)
-- after a start-up without fixture data render the same rows.
------------------------------------------------------------------------
local inbound=L.New(fx.spec)
CLOCK.offset=0
H=F.Boot(F.Database(),Before)
Settle(H)
local result=inbound:Inbound(H)
for _,b in ipairs(result.builds)do check(b.ok==true,'inbound: build '..b.id..' is admitted: '..tostring(b.why)) end
for _,r in ipairs(result.records)do check(r.ok==true,'inbound: '..r.category..' record of '..r.owner..' is accepted: '..tostring(r.why)) end
for _,category in ipairs({'lk','dummy','combined'})do
 L.Open(H,category)
 local got=L.RenderedRows(H)
 local fed=0
 for _,r in ipairs(got)do
  local owner=r.data.ownerKey
  local index;for _,e in ipairs(inbound:Expected(category))do if e.player.owner==owner then index=e end end
  check(index and index.player.build=='present' and not index.player.isLocal,'inbound '..category..': only fed players appear: '..tostring(owner))
  -- Rank differs (fewer rows); everything else must match the saved route.
  local e={player=index.player,dps=index.dps,average=index.average}
  local sig=RowCheck('inbound',category,r.rank,r,e,H)
  check(sig==first[category][owner],'inbound '..category..': '..owner..' renders as from saved data')
  fed=fed+1
 end
 local want=0;for _,e in ipairs(inbound:Expected(category))do if e.player.build=='present' and not e.player.isLocal then want=want+1 end end
 check(fed==want,'inbound '..category..': every fed player is ranked: '..fed..'/'..want)
end

local elapsed=os.clock()-started
print(string.format('PASS leaderboard_recovery_rows: %d builds + %d marker-only IDs (%d removal, %d retention, %s shape%s), %d players; lk/dummy/both rows, order, owner, build, exact ordinary and locked evidence, marker-only and missing-build rows, Open Build, reload, readiness, local plan, inbound cross-check checks=%d cpu=%.2fs',
 #fx.buildOrder,#fx.markerOrder,removalCount,retentionCount,SIZE.markerShape,
 SIZE.expireAfterDays and ('; retention markers expired after '..SIZE.expireAfterDays..' days') or '',#fx.players,checks,elapsed))
