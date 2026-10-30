-- Issue #144 passivity (family-144 preparation PD1/PD3 at 919ebe5): opening,
-- reading and selecting in the Build Library and the Leaderboard is passive.
-- A passive open must not create or normalize the saved build filters
-- (Controller.Filters now derives defaults without writing them), and
-- showing or selecting an incomplete build must not queue a Sync loadout
-- request (no implicit RequestLoadout in ShowBuild, the detail render or a
-- Leaderboard row selection). Explicit actions keep their behavior: SetFilter
-- writes (and keeps the legacy classFilter/pageSize fields current) and the
-- explicit lock-in preparation still requests an incomplete build.
-- Each scenario boots intentionally first, then takes its baselines (saved
-- bytes, writer trap, Sync WorkState, fake sends/actions) before the measured
-- calls. Synthetic offline evidence through the real TOC; native NOT_RUN.
-- A Leaderboard INCOMPLETE row could not be reached through a real
-- projection here (as in the PD3 trace); only the complete-row control is
-- measured and incomplete Leaderboard reachability stays UNKNOWN.
local F=dofile('tests/prototype/format5_support.lua')
local T=dofile('tests/prototype/startup_support.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end

local function Boot(filters)
 local db=F.Database()
 local profile=T.Profile(3,0)
 db.communityBuilds,db.loadoutEvidence=profile.communityBuilds,profile.loadoutEvidence
 db.communityBuilds['summary-only']={id='summary-only',title='Synthetic summary',author='Other-Realm',class='MAGE',
  postedAt=1,lastModified=1,needsFullBuild=true,loadoutAvailable=false,echoCount=79,fingerprintHash='abcd1234'}
 if filters then db.buildFilters={currentClassOnly=false,qualifiedOnly=false,scope='all',page=1,pageSize=20,search=''} end
 if filters=='full' then db.buildFilters.classFilter='MAGE' end
 local H=F.Boot(db)
 check(Nexus.StartupStatus().state~='pending','SETUP startup completed')
 local C=Nexus.BuildCatalog
 check(C.Get('summary-only') and not (C.Get('summary-only').echoes and #C.Get('summary-only').echoes>0),'SETUP incomplete record admitted')
 check(C.Get('synthetic-startup-1') and #C.Get('synthetic-startup-1').echoes>0,'SETUP complete control admitted')
 return H
end

local function Measure(H,label,fn)
 local S=Nexus.Sync
 local requests=0
 local original=S.RequestLoadout
 S.RequestLoadout=function(...) requests=requests+1;return original(...) end
 local beforeDB,beforeLegacy=F.Serialize(NexusDB),F.Serialize(WishlistRealizerDB)
 local filtersBefore=NexusDB.buildFilters
 local actions,sends=#H.actions,#H.sent
 local work=S.WorkState()
 fn()
 local after=S.WorkState()
 S.RequestLoadout=original
 return {label=label,requests=requests,saved=beforeDB==F.Serialize(NexusDB),legacy=beforeLegacy==F.Serialize(WishlistRealizerDB),
  filtersIdentity=filtersBefore==NexusDB.buildFilters,actions=#H.actions-actions,sends=#H.sent-sends,
  recovery=(after.recovery or 0)-(work.recovery or 0)}
end

local function Passive(r,why)
 check(r.saved and r.legacy,'EXPECT '..why..': saved bytes unchanged ('..r.label..')')
 check(r.requests==0 and r.recovery==0,'EXPECT '..why..': no loadout request or recovery work ('..r.label..') requests='..r.requests..' recovery+'..r.recovery)
 check(r.actions==0 and r.sends==0,'GUARD '..why..': no game action or wire send ('..r.label..')')
end

for _,filters in ipairs({false,true,'full'}) do
 for _,kind in ipairs({'show_library','select_incomplete','show_complete','show_incomplete','show_missing','refresh'}) do
  local H=Boot(filters)
  local CB=Nexus.CommunityBuilds
  local r=Measure(H,kind..' filters='..tostring(filters),function()
   if kind=='show_library' then CB.Show()
   elseif kind=='select_incomplete' then CB.Show();CB.Select('summary-only')
   elseif kind=='show_complete' then CB.ShowBuild('synthetic-startup-1')
   elseif kind=='show_incomplete' then CB.ShowBuild('summary-only')
   elseif kind=='show_missing' then CB.ShowBuild('absent-synthetic-build')
   else CB.Show();CB.Refresh();CB.Hide();CB.Show() end
  end)
  Passive(r,'passive library '..kind)
  if not filters then check(NexusDB.buildFilters==nil,'EXPECT a passive open creates no saved filter table ('..kind..')') end
  if filters==true then check(NexusDB.buildFilters.classFilter==nil,'EXPECT a passive open adds no legacy classFilter ('..kind..')') end
 end
end

-- Writer trap: same-value writes count too. The saved filters are replaced
-- (after boot, before the measured calls) by an empty proxy over the full
-- values that records every assignment.
do
 local H=Boot('full')
 local backing=NexusDB.buildFilters
 local writes={}
 local proxy=setmetatable({},{__index=backing,__newindex=function(_,k,v) writes[#writes+1]=tostring(k);rawset(backing,k,v) end})
 NexusDB.buildFilters=proxy
 local CB=Nexus.CommunityBuilds
 CB.Show();CB.Refresh();CB.ShowBuild('summary-only');CB.Select('synthetic-startup-1');CB.Refresh()
 check(#writes==0,'EXPECT no saved filter assignment at all during passive open/refresh/select, even same-value: '..table.concat(writes,','))
 check(NexusDB.buildFilters==proxy,'GUARD the saved filter table identity is kept')
 NexusDB.buildFilters=backing
end

-- Explicit choice through the real Mine scope button: saved, with the page
-- reset and the legacy fields current for older readers.
do
 local H=Boot(false)
 local CB=Nexus.CommunityBuilds
 CB.Show()
 check(NexusDB.buildFilters==nil,'EXPECT deriving the default view writes nothing')
 local mine=NexusCommunityBuildsFrame and NexusCommunityBuildsFrame._myBuildsBtn
 check(mine and mine.scripts.OnClick,'SETUP the real Mine scope button exists')
 mine:Click()
 local saved=NexusDB.buildFilters
 check(type(saved)=='table' and saved.scope=='mine' and saved.page==1 and saved.pageSize==20,'GUARD an explicit scope choice is saved with the page reset')
 check(saved.classFilter=='MAGE','GUARD an explicit filter choice keeps the legacy class field current')
end

-- Explicit lock-in of an incomplete selected build still asks for its
-- loadout (deliberate action, unchanged).
do
 local H=Boot(true)
 local CB=Nexus.CommunityBuilds
 CB.Show();CB.Select('summary-only')
 local r=Measure(H,'explicit lock-in on incomplete',function() CB.LockInSelected() end)
 check(r.requests==1,'GUARD the explicit lock-in still requests the incomplete loadout: '..r.requests)
end

-- Leaderboard: a complete-row selection is passive (control); see header for
-- the incomplete-row reachability gap.
do
 local H=Boot(true)
 local LB=Nexus.Leaderboard
 local r=Measure(H,'leaderboard show',function() LB.Show() end)
 Passive(r,'leaderboard open')
end

print('PASS l10n_passivity_library checks='..checks..' (synthetic; native NOT_RUN; incomplete Leaderboard row reachability UNKNOWN)')
