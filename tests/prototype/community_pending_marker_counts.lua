-- F-S2-1 (P3), regression-first: a "scan pending" catalog cursor step is not
-- a shipped (bundled) build. With the shipped DPS owner, the Community
-- projection counts provenance from what its catalog summary cursor returns
-- (core/ViewProjections.lua build job). When eight consecutive catalog slots
-- hold no admitted build (removal markers, for example), SummaryCursorNext
-- returns no row and the marker COPY_PENDING in the position of "has a
-- shipped copy", and the job counts it as one bundled build. The projection
-- summary, the Build Library window's diagnostic snapshot and its status line
-- ("%d bundled + %d overlay; %d available") then report shipped builds that
-- do not exist.
-- Healthy behaviour (EXPECT, fails at the baseline): bundledCount counts only
-- returned rows that have a shipped copy, in the projection summary, the
-- window's DiagnosticSnapshot and its status line.
-- Unchanged (GUARD, holds at the baseline): the listed rows, overlayCount and
-- availableCount; real shipped and saved rows keep their counts (scenario C:
-- a marker run too short to pend gives the same counts already); removal
-- markers stay represented and keep blocking their records, including a
-- shipped one; no game action.
-- Each scenario proves its precondition from the catalog's own Status counts
-- (SETUP): A and B hold a run of at least eight marker-only slots, so a cursor
-- step pends; C holds fewer than eight slots without an admitted build in
-- all, so no step can pend and its counts are a genuine control.
-- The status line is read once the window has rendered it from its
-- publication. The first publication renders the line before it records
-- itself as published (CommunityRenderer Refresh), so that line still shows
-- the catalog's Status counts, whose bundled count is every shipped map entry,
-- including one a removal marker blocks; any later Refresh renders it from
-- the publication, and the test calls the public one once (SETUP).
-- Real TOC boot, catalog, DPS owner, projection and Build Library window.
-- Saved data from leaderboard_fixture_support.lua (current v1 removal
-- markers); shipped records through the data\BundledBuilds.lua file hook the
-- catalog tests use. Artificial IDs and names only.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('community_pending_marker_counts')
local FILTERS={currentClassOnly=false,qualifiedOnly=false}
local SHIPPED={'ship-a','ship-b'}

-- The shipped-record shape the catalog tests boot with.
local function Shipped(id)
 return {id=id,title='Artificial shipped build '..id,author='Peer-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}}
end

-- markers: marker-only removal markers; shipped: also boot two shipped builds,
-- three saved builds and one shipped build whose ID a saved removal marker holds.
local function Boot(markers,shipped)
 local players={}
 if shipped then
  players={
   {name='Overlayone',class='MAGE'},
   {name='Overlaytwo',class='PRIEST'},
   {name='Overlaythree',class='MAGE'},
   {name='Shipgone',class='MAGE',build='tombstone',buildId='ship-gone'},
  }
 end
 local fx=L.New({removalMarkers=markers,markerShape='v1',players=players})
 F.fileHooks=shipped and {[ [[data\BundledBuilds.lua]] ]=function()
  Nexus.BundledBuilds.builds={['ship-a']=Shipped('ship-a'),['ship-b']=Shipped('ship-b'),
   ['ship-gone']=Shipped('ship-gone')}
 end} or nil
 local ok,H=pcall(F.Boot,fx:Install(F.Database()))
 F.fileHooks=nil
 if not ok then error(H,0) end
 for _=1,1000 do H.Advance(.05,.05) end
 return H,fx
end

-- The real projection, requested and pumped as the window does.
local function Project()
 local P=Nexus.ViewProjections
 local rows,summary,err
 for _=1,4000 do
  rows,summary,err=P.RequestBuilds(FILTERS)
  if rows or err~='pending' then break end
  P.PumpBuilds()
 end
 return rows,summary,err
end

local function StatusLine()
 local frame=NexusCommunityBuildsFrame
 return V.Plain(frame and frame._syncStatusText and frame._syncStatusText:GetText() or '')
end

-- The real Build Library window once its projection is published and current,
-- with the status line the next public Refresh renders from that publication;
-- also the line the first publication left.
local function Window(H)
 Nexus.CommunityBuilds.Show()
 for _=1,4000 do
  local d=Nexus.CommunityBuilds.DiagnosticSnapshot()
  if d.publishedPage>0 and d.projectionCurrent and not d.projectionPending and not d.projectionDirty then
   local first=StatusLine()
   Nexus.CommunityBuilds.Refresh()
   return Nexus.CommunityBuilds.DiagnosticSnapshot(),StatusLine(),first
  end
  H.Advance(.05,.05)
 end
 return nil,'',''
end

-- One catalog cursor call inspects at most eight slots (BuildCatalog
-- BUDGET.oneCallRows) and returns "scan pending" only when all eight held no
-- admitted build. From the catalog's Status counts, read before the window
-- opens: the most slots that can hold no admitted build (saved and shipped
-- copies beyond the admitted builds, and every marker, invalid, future and
-- retention slot); and the marker slots beyond those copies, which in these
-- fixtures (the one removed build keeps its shipped copy) are the marker-only
-- slots that admission places after every build slot, as one run.
local ONE_CALL_ROWS=8
local function Unadmitted()
 local s=Nexus.BuildCatalog.Status()
 local blocked=s.overlayCount+s.bundledCount-s.availableCount
 return blocked+s.tombstoneCount+s.invalidCount+s.futureCount+s.barrierCount,s.tombstoneCount-blocked
end

local function Sentence(bundled,overlay,available)
 return string.format('%d bundled + %d overlay; %d available',bundled,overlay,available)
end

local function Represented(ids)
 local n=0
 for _,id in ipairs(ids) do
  local state=Nexus.BuildCatalog.TombstoneState(id)
  if type(state)=='table' and state.state~='NONE' then n=n+1 end
 end
 return n
end

-- The counts the projection and the window must show for a fixture whose
-- returned rows are known: `bundled` shipped-only rows, `overlay` saved rows.
local function CheckCounts(tag,H,summary,bundled,overlay,pending)
 local check=pending and C.expect or C.guard
 C.guard(summary.overlayCount==overlay,tag..': the projection counts '..overlay..' saved rows',summary.overlayCount)
 C.guard(summary.availableCount==bundled+overlay,tag..': and '..(bundled+overlay)..' available rows',summary.availableCount)
 check(summary.bundledCount==bundled,tag..': the projection counts '..bundled..' shipped rows: only returned rows with a shipped copy',
  summary.bundledCount)
 local d,line,first=Window(H)
 C.setup(d~=nil,tag..': fixture: the Build Library window publishes its projection')
 if not d then return end
 print('OBSERVED',tag,'window bundled='..printable(d.bundledCount)..' overlay='..printable(d.overlayCount)
  ..' available='..printable(d.availableCount),'status='..line)
 print('OBSERVED',tag,'status left by the first publication='..first)
 C.guard(d.overlayCount==overlay and d.availableCount==bundled+overlay,
  tag..': the window diagnostic keeps the saved and available counts',printable(d.overlayCount)..'/'..printable(d.availableCount))
 check(d.bundledCount==bundled,tag..': the window diagnostic reports '..bundled..' shipped builds',d.bundledCount)
 C.setup(line:find(' bundled + ',1,true)~=nil,tag..': fixture: the status line shows its count sentence',line)
 C.setup(d.publishedPage>0 and d.projectionCurrent
  and line:find(Sentence(tonumber(d.bundledCount) or -1,tonumber(d.overlayCount) or -1,tonumber(d.availableCount) or -1),1,true)~=nil,
  tag..': fixture: the status line is rendered from the window\'s publication',line)
 check(line:find(Sentence(bundled,overlay,bundled+overlay),1,true)~=nil,
  tag..': the status line says "'..Sentence(bundled,overlay,bundled+overlay)..'"',line)
end

-- A. The reproduced case: sixteen marker-only slots and nothing else.
C.scenario('A sixteen marker-only slots',function()
 local H,fx=Boot(16,false)
 C.setup(Nexus.StartupStatus().coreReady==true,'A: fixture: start-up reached core-ready')
 C.setup(#fx.markerOrder==16 and Represented(fx.markerOrder)==16,'A: fixture: the sixteen saved removal markers are represented',
  Represented(fx.markerOrder))
 local status=Nexus.BuildCatalog.Status()
 C.setup(status.bundledCount==0 and status.availableCount==0,'A: fixture: the catalog holds no shipped and no available build',
  printable(status.bundledCount)..'/'..printable(status.availableCount))
 local _,markerOnly=Unadmitted()
 C.setup(markerOnly>=ONE_CALL_ROWS,'A: fixture: at least eight marker-only slots form one run, so a cursor step pends',markerOnly)
 local rows,summary,err=Project()
 C.setup(rows~=nil and summary~=nil,'A: fixture: the projection publishes within its bound',err)
 rows,summary=rows or {},summary or {}
 print('OBSERVED','A','rows='..#rows,'bundled='..printable(summary.bundledCount),'overlay='..printable(summary.overlayCount),
  'available='..printable(summary.availableCount))
 C.guard(#rows==0,'A: the markers list nothing',#rows)
 CheckCounts('A',H,summary,0,0,true)
 C.guard(Represented(fx.markerOrder)==16,'A: every marker is still represented after the reads')
 C.guard(#H.actions==0,'A: no game action',#H.actions)
end)

-- B. Two shipped builds, three saved builds and a shipped build blocked by
-- its saved removal marker, followed by a run of sixteen marker-only slots.
C.scenario('B shipped and saved builds before sixteen marker-only slots',function()
 local H,fx=Boot(16,true)
 C.setup(Nexus.StartupStatus().coreReady==true,'B: fixture: start-up reached core-ready')
 local saved={}
 for _,p in ipairs(fx.players) do if p.build=='present' then saved[#saved+1]=p.buildId end end
 C.setup(#saved==3,'B: fixture: three saved builds',#saved)
 C.setup(Represented(fx.markerOrder)==17,'B: fixture: the sixteen marker-only markers and the shipped build\'s marker are represented',
  Represented(fx.markerOrder))
 local _,markerOnly=Unadmitted()
 C.setup(markerOnly>=ONE_CALL_ROWS,'B: fixture: at least eight marker-only slots follow the builds in one run, so a cursor step pends',
  markerOnly)
 local rows,summary,err=Project()
 C.setup(rows~=nil and summary~=nil,'B: fixture: the projection publishes within its bound',err)
 rows,summary=rows or {},summary or {}
 local listed={}
 for _,b in ipairs(rows) do listed[b.id]=true end
 local all=true
 for _,id in ipairs(SHIPPED) do all=all and listed[id]==true end
 for _,id in ipairs(saved) do all=all and listed[id]==true end
 C.setup(all and #rows==5,'B: fixture: the two shipped and three saved builds are the listed rows',#rows)
 print('OBSERVED','B','rows='..#rows,'bundled='..printable(summary.bundledCount),'overlay='..printable(summary.overlayCount),
  'available='..printable(summary.availableCount))
 C.guard(not listed['ship-gone'] and Nexus.BuildCatalog.Get('ship-gone')==nil,
  'B: the saved removal marker still blocks its shipped build')
 CheckCounts('B',H,summary,2,3,true)
 C.guard(Represented(fx.markerOrder)==17,'B: every marker is still represented after the reads')
 C.guard(#H.actions==0,'B: no game action',#H.actions)
end)

-- C. The same builds with only three marker-only slots: no step can pend
-- (proved from the catalog counts), so these counts hold at the baseline and
-- must keep holding.
C.scenario('C shipped and saved builds before three marker-only slots',function()
 local H,fx=Boot(3,true)
 C.setup(Nexus.StartupStatus().coreReady==true,'C: fixture: start-up reached core-ready')
 C.setup(Represented(fx.markerOrder)==4,'C: fixture: the markers are represented',Represented(fx.markerOrder))
 local most=Unadmitted()
 C.setup(most<ONE_CALL_ROWS,'C: fixture: fewer than eight slots hold no admitted build, so no cursor step can pend',most)
 local rows,summary,err=Project()
 C.setup(rows~=nil and summary~=nil,'C: fixture: the projection publishes within its bound',err)
 rows,summary=rows or {},summary or {}
 C.guard(#rows==5,'C: the two shipped and three saved builds are listed',#rows)
 C.guard(Nexus.BuildCatalog.Get('ship-gone')==nil,'C: the saved removal marker still blocks its shipped build')
 CheckCounts('C',H,summary,2,3,false)
 C.guard(#H.actions==0,'C: no game action',#H.actions)
end)

C.finish('(a pending catalog cursor step is not counted as a shipped build; returned rows keep their counts)')
