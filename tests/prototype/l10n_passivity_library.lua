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

-- Early review PD1-P2-1 (565b2d2): a saved page beyond the projected pages
-- is clamped for the view only. A passive open, render, refresh, select and
-- hide/reopen never call the saved-filter writer (Controller.SetFilter) or
-- add page/pageSize/classFilter defaults; the explicit Prev/Next buttons
-- save the page next to the DISPLAYED page (page 2 from a shown page 3, not
-- 98 from a saved 99); a disabled boundary button writes nothing; a scope
-- change resets the view without a stale clamp. A future-format (read-only)
-- root keeps its saved bytes through both passive and explicit steps.
-- Each phase is measured from a baseline taken after an intentional boot
-- and the same idle settling as its control.
local function ControllerOf()
 for i=1,40 do
  local n,v=debug.getupvalue(Nexus.CommunityBuilds.Select,i)
  if not n then break end
  if n=='ControllerInstance' then return v() end
 end
 error('SETUP controller upvalue missing')
end
local function Saved99()
 return {page=99,currentClassOnly=false,qualifiedOnly=false,scope='all',search='',custom={keep=17,nested={deep=true}}}
end
local function PageBoot(readOnly)
 local db=readOnly and F.Database({version=6}) or F.Database()
 local profile=T.Profile(45,0)
 db.communityBuilds,db.loadoutEvidence=profile.communityBuilds,profile.loadoutEvidence
 db.buildFilters=Saved99()
 local H=F.Boot(db)
 check(Nexus.StartupStatus().state~='pending','SETUP page fixture startup completed')
 return H
end
local function Settle(H) for _=1,60 do H.Advance(.05,.05) end end
local function Writes()
 local C=ControllerOf();local calls={};local old=C.SetFilter
 C.SetFilter=function(k,v) calls[#calls+1]=tostring(k)..'='..tostring(v);return old(k,v) end
 return calls,function() C.SetFilter=old end
end
local function Shown()
 local f=NexusCommunityBuildsFrame
 local a,b=tostring(f._pageText:GetText()):match('^(%d+) / (%d+)$')
 return tonumber(a),tonumber(b),f._prevPageBtn:IsEnabled(),f._nextPageBtn:IsEnabled()
end

-- Matched control: the same boot and idle settling with no window makes no
-- filter write, so later calls are the UI's own.
do
 local H=PageBoot(false)
 local calls,restore=Writes()
 Settle(H)
 restore()
 check(#calls==0 and NexusDB.buildFilters.page==99,'SETUP idle control: no filter write, saved page 99 kept')
end

do
 local H=PageBoot(false)
 local CB=Nexus.CommunityBuilds
 local saved=NexusDB.buildFilters
 local custom=saved.custom
 local savedBytes=F.Serialize(saved)
 local calls,restore=Writes()
 local actions,sends=#H.actions,#H.sent
 CB.Show();Settle(H)
 local page,count,prev,nxt=Shown()
 check(count and count>=3,'SETUP the fixture projects several pages: '..tostring(count))
 check(page==count and prev and not nxt,'EXPECT the view shows the clamped last page with truthful controls: '..tostring(page)..' / '..tostring(count))
 CB.Refresh();Settle(H)
 CB.Select('synthetic-startup-1');CB.Refresh();CB.Hide();CB.Show();Settle(H)
 page,count=Shown()
 check(page==count,'EXPECT refresh, select and hide/reopen keep the clamped view')
 check(#calls==0,'EXPECT passive open/refresh/select/reopen never call the saved-filter writer: '..table.concat(calls,','))
 check(NexusDB.buildFilters==saved and saved.page==99 and saved.pageSize==nil and saved.classFilter==nil,
  'EXPECT the saved request (page 99) stays, and no default is added')
 check(F.Serialize(saved)==savedBytes and saved.custom==custom and custom.nested.deep==true,'EXPECT saved filter bytes, unknown and nested fields unchanged')
 check(#H.actions==actions and #H.sent==sends,'GUARD no game action or send')
 -- Explicit Prev from the displayed page.
 NexusCommunityBuildsFrame._prevPageBtn:Click();Settle(H)
 check(#calls==1 and calls[1]=='page='..(count-1),'EXPECT Prev saves the page before the DISPLAYED one: '..table.concat(calls,','))
 check(saved.page==count-1 and saved.pageSize==20,'EXPECT the explicit page choice is saved with its defaults')
 page=Shown()
 check(page==count-1,'EXPECT the view follows the explicit page')
 -- Explicit Next to the last page; the disabled Next then writes nothing.
 NexusCommunityBuildsFrame._nextPageBtn:Click();Settle(H)
 check(#calls==2 and calls[2]=='page='..count and saved.page==count,'EXPECT Next saves the page after the displayed one')
 local _,_,_,nextEnabled=Shown()
 check(not nextEnabled,'SETUP Next is disabled on the last page')
 NexusCommunityBuildsFrame._nextPageBtn:Click()
 check(#calls==2,'EXPECT a disabled boundary button writes nothing')
 -- A scope change resets the view: no stale clamp.
 NexusCommunityBuildsFrame._myBuildsBtn:Click();Settle(H)
 page=Shown()
 check(saved.scope=='mine' and saved.page==1 and page==1,'EXPECT an explicit scope change shows page 1, not a stale clamp')
 restore()
end

-- Future-format (read-only) root: the same passive and explicit steps never
-- touch the saved root; the explicit page stays session-only.
do
 local H=PageBoot(true)
 local CB=Nexus.CommunityBuilds
 local before=F.Serialize(NexusDB)
 local calls,restore=Writes()
 CB.Show();Settle(H)
 local page,count=Shown()
 check(count and page==count and #calls==0,'EXPECT read-only root: the clamped view, no writer call')
 check(F.Serialize(NexusDB)==before,'EXPECT read-only root: saved bytes unchanged by the passive open')
 NexusCommunityBuildsFrame._prevPageBtn:Click();Settle(H)
 page=Shown()
 check(#calls==1 and page==count-1,'EXPECT read-only root: Prev still moves the view to the displayed page before')
 check(F.Serialize(NexusDB)==before,'EXPECT read-only root: the explicit page is session-only, saved bytes unchanged')
 restore()
end

print('PASS l10n_passivity_library checks='..checks..' (synthetic; native NOT_RUN; incomplete Leaderboard row reachability UNKNOWN)')
