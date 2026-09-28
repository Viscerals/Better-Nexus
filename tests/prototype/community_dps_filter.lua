-- Build Library DPS-record filter (BN-CONTROL-COMMUNITY-DPS-FILTER-001).
-- The qualifier is one fixed-label check box, "Require both DPS records"
-- (Training Dummy + Lich King): checked requires both eligible records that
-- this client holds; unchecked imposes no DPS-record requirement. "All
-- Shared" / "My Builds" stay the separate scope controls.
--
-- Real TOC boot, catalog, DpsCapture, projection, controller and Community
-- window handlers; synthetic players (leaderboard_fixture_support.lua). The
-- expected row sets below are written from the owner's stated semantics and
-- the existing pairing rule (one character's own Dummy + Lich King pair on the
-- loadout), not read back from the implementation. Class, scope and search
-- are fixed so no other filter can hide a failed expectation.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local function Players()
 return {
  {name='PrototypeTester',class='MAGE',isLocal=true,variant=30,ordinary=60},
  {name='Nodps',class='MAGE',variant=1},
  {name='Dummyonly',class='MAGE',variant=2,dps={dummy=41000}},
  {name='Lkonly',class='MAGE',variant=3,dps={lk=42000}},
  {name='Bothdps',class='MAGE',variant=4,dps={dummy=43000,lk=44000}},
  -- A zero Dummy record never counts as a record.
  {name='Zerodummy',class='MAGE',variant=5,dps={dummy=0,lk=45000}},
  -- Same loadout, Dummy from one character and Lich King from another:
  -- no single character has the pair, so the loadout does not qualify.
  {name='Crossa',class='MAGE',variant=6,dps={dummy=46000}},
  {name='Crossb',class='MAGE',variant=6,build='missing',dps={lk=47000}},
 }
end
local H,fx,frame
local function Boot(dbOptions)
 fx=L.New({players=Players()})
 H=F.Boot(fx:Install(F.Database(dbOptions or {version=2})),function(h) h.playerLevel=60 end)
 for _=1,400 do H.Advance(.05,.05) end
 Nexus.CommunityBuilds.Show()
 frame=assert(NexusCommunityBuildsFrame)
end
local function Id(name) for _,p in ipairs(fx.players) do if p.name==name then return p.buildId end end end
local function Set(list) local s={} for _,n in ipairs(list) do s[Id(n)]=true end return s end
-- Independently expected remote rows (the local build is checked separately).
local REMOTE={'Nodps','Dummyonly','Lkonly','Bothdps','Zerodummy','Crossa'}
local UNCHECKED=REMOTE
local CHECKED={'Bothdps'}
-- The build cards the window actually binds. The list is virtual (only the
-- cards in view are bound), so the list is scrolled through with the
-- window's own ScrollTo and the bound cards are collected at each position.
local function Visible(out)
 for _,f in ipairs(H.frames) do
  if f.buildId and f:IsVisible() then out[f.buildId]=true end
 end
end
local function Shown()
 local out={}
 for step=0,40 do
  Nexus.CommunityBuilds.ScrollTo(step*92)
  for _=1,3 do H.Advance(.05,.05) end
  Visible(out)
 end
 Nexus.CommunityBuilds.ScrollTo(0);H.Advance(.05,.05)
 return out
end
local function Diag() return Nexus.CommunityBuilds.DiagnosticSnapshot() end
local function Settle()
 for _=1,4000 do
  local d=Diag()
  if d.projectionCurrent and not d.projectionPending and not d.projectionDirty then return d end
  H.Advance(.05,.05)
 end
 error('the Community projection did not settle')
end
local function Remote(set)
 local s={}
 for _,n in ipairs(REMOTE) do if set[Id(n)] then s[#s+1]=n end end
 return table.concat(s,',')
end
local function Expect(list,label)
 local d=Settle()
 local shown=Shown()
 local want=table.concat((function() local t={} for _,n in ipairs(REMOTE) do for _,m in ipairs(list) do if m==n then t[#t+1]=n end end end return t end)(),',')
 check(Remote(shown)==want,label..': the shown remote builds are exactly ['..want..'], got ['..Remote(shown)..']')
 for id in pairs(shown) do
  local known=false
  for _,p in ipairs(fx.players) do if p.buildId==id then known=true end end
  check(known,label..': only fixture builds are shown: '..tostring(id))
 end
 return d,shown
end
-- The client flips a check box's own check before its OnClick runs; the
-- harness does not, so a check box click here does the same.
local function Click(b)
 assert(b:IsVisible() and b:IsEnabled(),'visible enabled control')
 if b.kind=='CheckButton' then b:SetChecked(not b:GetChecked()) end
 b:Click()
end
local function Checked() return frame._qualifiedBtn:GetChecked()==true end
-- The controller's filter, as the window's diagnostic reads it from the
-- controller (not from the check box).
local function Filter() return Nexus.CommunityBuilds.DiagnosticSnapshot().filterQualifiedOnly end

-- 1. The control: one fixed label, a checked state that is the filter.
Boot()
local box=frame._qualifiedBtn
check(box.kind=='CheckButton','the DPS-record qualifier is a check box: '..tostring(box.kind))
local label=assert(frame._qualifiedLabel,'the check box has its own label')
check(label:GetText()=='Require both DPS records','the label is fixed: '..tostring(label:GetText()))
check(Filter()==true and Checked(),'the saved default (require both records) is shown checked')
-- Fixed controls for the rest of the file: every class, All Shared, no search.
if frame._classDropBtn:GetText()~='All Classes' then Click(frame._classDropBtn) end
if frame._scopeBtn:IsEnabled() then Click(frame._scopeBtn) end
check(frame._classDropBtn:GetText()=='All Classes' and not frame._scopeBtn:IsEnabled() and frame._myBuildsBtn:IsEnabled(),
 'fixture: every class, All Shared scope')
check((frame._searchBox:GetText() or '')=='','fixture: no search text')
local _,shown=Expect(CHECKED,'checked')
check(not shown[Id('PrototypeTester')],'checked: the local build without records is not shown')

-- 2. Toggling: the label never changes; the check follows the filter; the
-- rows follow the check. Repeated toggles.
for round=1,2 do
 Click(box)
 check(label:GetText()=='Require both DPS records','round '..round..': the label did not change')
 check(Filter()==false and not Checked(),'round '..round..': unchecked means no DPS-record requirement')
 Expect(UNCHECKED,'round '..round..' unchecked')
 Click(box)
 check(Filter()==true and Checked(),'round '..round..': checked again requires both records')
 Expect(CHECKED,'round '..round..' checked')
end

-- 3. Pending state: right after the click the check shows the request, and
-- the window does not present the old rows as the new filter's result.
Click(box)
local d=Diag()
-- The projection is deferred here (the click's own refresh returns pending).
check(d.projectionPending==true and d.projectionCurrent==false,'fixture: the new filter\'s projection is still pending after the click')
check(frame._resultText:GetText():find('Updating results',1,true)~=nil,
 'while the new filter is prepared the result line says so: '..tostring(frame._resultText:GetText()))
check(not Checked() and Filter()==false,'and the check already shows the requested filter')
Expect(UNCHECKED,'after the pending state')
check(not frame._resultText:GetText():find('Updating results',1,true),'the published result replaces the pending text')

-- 3b. From an empty checked result: while the unchecked projection is
-- pending, the list does not say that no build matches the current filters.
do
 Click(box);Expect(CHECKED,'fixture: checked again')
 local search=frame._searchBox
 search:SetText('Nodps');search:GetScript('OnTextChanged')(search,true)
 Settle()
 check(Remote(Shown())=='' and frame._emptyState:IsShown(),'checked with a search for the build without records: empty result shown')
 Click(box)
 local p=Diag()
 check(p.projectionPending==true,'fixture: the unchecked projection is pending')
 check(not frame._emptyState:IsShown() and frame._resultText:GetText():find('Updating results',1,true),
  'pending: no "no builds match" text, the result line says it is updating')
 -- A scroll re-binds the last rows; the empty text must not come back.
 Nexus.CommunityBuilds.ScrollTo(0)
 check(Diag().projectionPending==true and not frame._emptyState:IsShown(),'pending after a scroll: still no "no builds match" text')
 Settle()
 check(Remote(Shown())=='Nodps' and not frame._emptyState:IsShown(),'settled: the build without records is shown')
 search:SetText('');search:GetScript('OnTextChanged')(search,true)
 Expect(UNCHECKED,'search cleared, unchecked')
end

-- 4. Refresh, close/reopen and the scope controls keep the filter.
Nexus.CommunityBuilds.Refresh();check(not Checked() and Filter()==false,'refresh keeps the unchecked filter')
Nexus.CommunityBuilds.Hide();Nexus.CommunityBuilds.Show();Expect(UNCHECKED,'reopened unchecked')
check(not Checked(),'reopen shows it unchecked')
Click(box);Nexus.CommunityBuilds.Hide();Nexus.CommunityBuilds.Show()
check(Checked() and Filter()==true,'reopen shows it checked');Expect(CHECKED,'reopened checked')
Click(frame._myBuildsBtn)
check(Checked() and Filter()==true,'My Builds keeps the DPS-record filter')
local d2=Settle()
check(Remote(Shown())=='','My Builds with the filter checked: no remote build is shown')
Click(frame._scopeBtn);Expect(CHECKED,'All Shared again, still checked')
check(label:GetText()=='Require both DPS records' and frame._scopeBtn:GetText()=='All Shared','the scope button keeps its own label')

-- 5. Side effects: matched runs with and without filter clicks, same schedule.
-- No Sync request or broadcast, no catalog or DPS write, no assignment,
-- Auto or Orb change; addon traffic identical.
local function Run(clicks)
 Boot()
 if frame._classDropBtn:GetText()~='All Classes' then Click(frame._classDropBtn) end
 if frame._scopeBtn:IsEnabled() then Click(frame._scopeBtn) end
 Settle()
 local calls={}
 local function Count(owner,names) for _,n in ipairs(names) do local real=owner[n]
  if type(real)=='function' then owner[n]=function(...) calls[#calls+1]=n;return real(...) end end end end
 Count(Nexus.Sync,{'RequestSync','BroadcastBuild','BroadcastMine','BroadcastDpsRecord','BroadcastDps','BroadcastDelete'})
 Count(Nexus.BuildCatalog,{'Put','Delete','Remove'})
 Count(Nexus.DpsCapture,{'ReceiveRecord','Record','Clear'})
 Count(Nexus.GameAdapter,{'SetLoadoutWishlist','SetLoadoutWishlistIdentity','SetFirstLoadoutWishlistIdentity','Take','Banish','Reroll','Freeze','Activate','Save','LockPerk','UnlockPerk'})
 local sent=#H.sent
 local dps0=F.Serialize(NexusDB.dpsCapture or {})
 local auto0=Nexus.RecomputeStats().autoEnabled
 local orb0=Nexus.OrbRuntime.BlocksOrdinary()
 for i=1,6 do
  if clicks then Click(frame._qualifiedBtn) end
  for _=1,20 do H.Advance(.05,.05) end
 end
 local out={calls=table.concat(calls,','),sent=#H.sent-sent,dps=F.Serialize(NexusDB.dpsCapture or {})==dps0,
  auto=Nexus.RecomputeStats().autoEnabled==auto0,orb=Nexus.OrbRuntime.BlocksOrdinary()==orb0}
 return out
end
do
 local control,clicked=Run(false),Run(true)
 check(clicked.calls=='' and control.calls=='','no Sync, catalog, DPS, assignment or game call: ['..clicked.calls..']')
 check(clicked.sent==control.sent,'addon traffic with filter clicks equals the matched run: '..clicked.sent..' vs '..control.sent)
 check(clicked.dps and clicked.auto and clicked.orb,'DPS records, Auto and Orb state unchanged')
end

-- 6. A read-only (protected) profile: the change applies to the session and
-- the saved data stays byte for byte.
do
 local db=F.Database({version=6,mutate=function(d) d.buildFilters={qualifiedOnly=true} end})
 fx=L.New({players=Players()})
 local before
 H=F.Boot(db,function(h) h.playerLevel=60 end)
 before=F.Serialize(NexusDB)
 for _=1,200 do H.Advance(.05,.05) end
 Nexus.CommunityBuilds.Show();frame=assert(NexusCommunityBuildsFrame)
 check(frame._qualifiedBtn:GetChecked()==true,'read-only session: the saved checked filter is shown')
 Click(frame._qualifiedBtn)
 check(frame._qualifiedBtn:GetChecked()~=true and Nexus.CommunityBuilds.DiagnosticSnapshot().filterQualifiedOnly==false,'read-only session: the change applies to the session')
 check(F.Serialize(NexusDB)==before,'read-only session: the saved data is unchanged')
end

-- 7. Geometry in the existing Community layout model (6 px per character,
-- 22 px caps) and the conservative one (7 px): the check box and its label
-- fit their box at font scales 0.75-2, and the box does not overlap the scope
-- controls.
do
 local LM=Nexus.LayoutMetrics
 for _,s in ipairs({0.75,1,1.25,1.5,2}) do
  local layout=LM.Community({width=1040,height=640,fontScale=s,labels={
   search='Search title, author, or description',scope='All Shared',mine='My Builds',
   class='Current Class Only',qualified='Require both DPS records',sort='Sort: Highest DPS',sync='Listening...',share='Share Build'}})
  local q,scope,mine=layout.boxes.qualified,layout.boxes.scope,layout.boxes.mine
  for _,m in ipairs({{'default',6},{'conservative',7}}) do
   check(22+4+#'Require both DPS records'*m[2]*s<=q.w,'scale '..s..' '..m[1]..': check box and label fit: '..q.w)
  end
  for _,o in ipairs({scope,mine}) do
   local apart=q.y>=o.y+o.h or o.y>=q.y+q.h or q.x>=o.x+o.w or o.x>=q.x+q.w
   check(apart,'scale '..s..': the check box does not overlap a scope button')
  end
  check(q.x+q.w<=1040-20,'scale '..s..': inside the window')
 end
end

print('PASS community_dps_filter checks='..checks)
