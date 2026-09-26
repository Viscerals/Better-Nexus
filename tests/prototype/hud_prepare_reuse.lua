-- HUD preparation reuses its DPS reads and does not multiply model copies.
--
-- Native profiling of 20dabcd: hud.prepare averaged ~26 ms per call while
-- Auto rolled (max 272 ms), and Auto prepares the HUD for every board. Each
-- preparation read this character's best rows, its player summary and the
-- exact-set personal and global rows. Those reads walk every stored character
-- row (twice for Lich King: best row and rank) and, when the exact set has no
-- personal record, every personal row, and they materialize full records.
-- Then the view model copied the complete display input about six times.
--
-- Everything here runs through the real TOC, the real runtime, the real
-- DpsCapture store and the real Panel. Every displayed DPS value is compared
-- with the public DpsCapture reads made at that moment (the uncached oracle).
-- Stored-row walks are counted by a pairs() wrapper that sees only the stored
-- DPS tables; copies are counted by the view model's own copiedTables count.
-- No timing or memory figure is asserted.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local FILLERS=240
local realPairs=pairs

local function Players()
 local list={
  {name='PrototypeTester',class='MAGE',dps={lk=39000,dummy=38000},isLocal=true,variant=30,ordinary=60},
  {name='Alpha',class='MAGE',dps={lk=52000,dummy=48000},variant=10,ordinary=60},
  {name='Bravo',class='PRIEST',dps={lk=61000,dummy=57000},variant=20,ordinary=60},
 }
 local classes={'WARRIOR','PALADIN','HUNTER','ROGUE','PRIEST','DEATHKNIGHT','SHAMAN','MAGE','WARLOCK','DRUID'}
 for i=1,FILLERS do
  list[#list+1]={name='Filler'..i,class=classes[(i-1)%10+1],dps={lk=30000+i,dummy=29000+i},variant=100+i}
 end
 return list
end

-- Personal records of the local character: one for Alpha's exact set, and
-- forty other sets, so an exact set without a record walks them all.
local function AddPersonal(db,fx)
 local E=L.Evidence()
 local function Row(ord,dps,category)
  local fp=L.Fingerprint(ord)
  return {dps=dps,level=80,ts=L.STAMP+dps,duration=category=='lk' and 120 or 180,
   player=F.NAME,class='MAGE',ownerKey=F.OWNER,realm='ebonhold',echoes=L.DpsRows(ord),
   fingerprint=fp,loadoutHash=E.CompatibilityHash(fp),evidenceKey=E.Fingerprint(L.DpsRows(ord)),
   protocolVersion=7,ownerVerified=true}
 end
 local personal=db.dpsCapture.personalBest or {}
 db.dpsCapture.personalBest=personal
 local alpha=fx.players[2].ordinary
 personal[L.Fingerprint(alpha)]={dummy=Row(alpha,20000,'dummy'),lk=Row(alpha,21000,'lk')}
 for v=0,39 do
  local ord=L.OrdinaryRows(5000+v)
  personal[L.Fingerprint(ord)]={dummy=Row(ord,10000+v,'dummy'),lk=Row(ord,11000+v,'lk')}
 end
 return db
end

local function Wishlist(ord)
 local out={}
 for i,r in ipairs(ord)do out[i]={spellId=r.spellId,quality=r.quality,stacks=r.stacks}end
 return out
end

local H,fx
local function Boot(version)
 fx=L.New({players=Players()})
 local db=AddPersonal(fx:Install(F.Database({version=version})),fx)
 H=F.Boot(db,function(h) h.playerLevel=60 end)
 check(Nexus.StartupStatus().coreReady==true,'fixture: start-up completed (settings format '..version..')')
 if _G.NexusQuickStart and _G.NexusQuickStart:IsShown() then _G.NexusQuickStart:Hide();H.Advance(.2) end
 H.Board({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}})
 H.Notify();H.Advance(1)
end

local function Step()
 Nexus.RequestRecompute();H.Advance(.4)
end

local function UseWishlist(name,ord)
 check(Nexus.GameAdapter.SetFirstLoadoutWishlistIdentity(name,Wishlist(ord)),'fixture: Wishlist '..name..' set')
 for _=1,3 do Step() end
 local model=Nexus.Panel._lastModel
 local echoes=model and model.progress and model.progress.dpsEchoes
 check(type(echoes)=='table' and Nexus.DpsCapture.GetEchoKey(echoes)==L.Fingerprint(ord),
  'fixture: the HUD shows the exact Echo set of '..name)
end

-- The stored DPS tables the reads walk: the bound payload of this session.
local watched,visits={},0
local function Watch()
 watched={}
 local bundle=rawget(NexusDB,'authorityBundle')
 local dps=bundle and rawget(bundle,'dpsCapture')
 check(type(dps)=='table' and type(dps.characterBest)=='table' and type(dps.personalBest)=='table',
  'fixture: the stored DPS payload is found')
 watched[dps.characterBest.dummy]=true;watched[dps.characterBest.lk]=true;watched[dps.personalBest]=true
end
local function CountingPairs(t)
 if not watched[t] then return realPairs(t) end
 local k
 return function()
  local v;k,v=next(t,k)
  if k~=nil then visits=visits+1 end
  return k,v
 end,t,nil
end
-- n real HUD preparations of the current panel input; returns stored rows walked.
local function Refresh(n)
 visits=0
 pairs=CountingPairs
 local ok,err=pcall(function()
  for _=1,n do assert(Nexus.RefreshHudView()~=nil,'refresh returned') end
 end)
 pairs=realPairs
 assert(ok,err)
 return visits
end

local function Tables(t,seen)
 if type(t)~='table' then return 0 end
 seen=seen or {};if seen[t] then return 0 end;seen[t]=true
 local n=1;for k,v in realPairs(t)do n=n+Tables(k,seen)+Tables(v,seen)end;return n
end
local function Same(a,b) return F.Serialize(a)==F.Serialize(b) end
local function Dps(row) return type(row)=='table' and row.dps or nil end

-- Uncached oracle: the public reads, now, for the player and the Echo set the
-- HUD shows.
local function Oracle(model)
 local D=Nexus.DpsCapture
 local me=UnitName('player')
 local echoes=model.progress.dpsEchoes
 local gd=D.GetLeaderboardForEchoes(echoes,'dummy');local gl=D.GetLeaderboardForEchoes(echoes,'lk')
 return {bestDps={dummy=D.GetCharacterBest('dummy',me),lk=D.GetCharacterBest('lk',me),info=D.GetPlayerInfo(me)},
  performance={dummy={personal=D.GetPersonalBestForEchoes(echoes,'dummy'),global=gd[1]},
   lk={personal=D.GetPersonalBestForEchoes(echoes,'lk'),global=gl[1]}}}
end
local function Shown(model)
 return {bestDps=model.bestDps,performance=model.progress.performance}
end
local function MatchesOracle(label)
 local model=assert(Nexus.Panel._lastModel,'a prepared model is on the panel')
 local shown,expected=Shown(model),Oracle(model)
 check(Same(shown,expected),label..': every HUD DPS value equals the uncached reads')
 return shown
end

local function Projection() return Nexus.DpsCapture.HudProjectionStats() end
local function Snapshot() return Nexus.HudSnapshotStats() end

------------------------------------------------------------------------
-- A writable profile.
------------------------------------------------------------------------
Boot(2)
UseWishlist('Alpha set',fx.players[2].ordinary)
Watch()

-- 0. The counter sees the walks it must rule out. A DPS revision rebuilds
-- the projection once and that rebuild walks every stored character row.
do
 local before=Projection()
 check(fx:Receive('Filler7','lk',{dps=30500}),'fixture: a received record is stored')
 local walked=Refresh(1)
 check(walked>=2*FILLERS,'control: the rebuild after a DPS revision walks the stored rows: '..walked)
 check(Projection().builds==before.builds+1,'control: and builds the projection once')
 local shown=MatchesOracle('after a DPS revision')
 check(Dps(shown.bestDps.dummy)==38000 and Dps(shown.bestDps.lk)==39000,'the character best rows are shown')
 check(Dps(shown.performance.dummy.personal)==20000 and Dps(shown.performance.lk.personal)==21000,
  'the personal exact-set rows are shown')
 check(Dps(shown.performance.dummy.global)==48000 and Dps(shown.performance.lk.global)==52000,
  'the global exact-set rows are shown')
end

-- 1. Repeated identical preparations walk no stored row, build no projection
-- and copy the model once each (the view model's defensive result copy).
do
 local p0,s0=Projection(),Snapshot()
 local walked=Refresh(50)
 local p1,s1=Projection(),Snapshot()
 check(walked==0,'50 identical HUD preparations walk no stored DPS row: '..walked)
 check(p1.builds==p0.builds and p1.hits==p0.hits+50,
  'they reuse the projection: builds +'..(p1.builds-p0.builds)..', hits +'..(p1.hits-p0.hits))
 check(s1.skipped==s0.skipped+50,'the view model reuses its prepared model: skipped +'..(s1.skipped-s0.skipped))
 local model=Tables(Nexus.Panel._lastModel)
 local copied=(s1.copiedTables-s0.copiedTables)/50
 print('HUD_REUSE identical copiedTables/prep',copied,'model tables',model)
 check(copied<=model+4,'an identical preparation copies at most one model: '..copied..' tables for a '..model..'-table model')
 MatchesOracle('after 50 identical preparations')
end

-- 2. A changed display input (here the update notice) rebuilds the view model
-- but not the DPS projection: one private snapshot plus one result copy.
do
 local updates=Nexus.Updates
 local original=updates.GetVisibleNotice
 local n=0
 updates.GetVisibleNotice=function() n=n+1;return {title='Synthetic notice '..n,kind='test'} end
 local p0,s0=Projection(),Snapshot()
 local ok,walked=pcall(Refresh,20)
 updates.GetVisibleNotice=original
 assert(ok,walked)
 local p1,s1=Projection(),Snapshot()
 check(walked==0,'rebuilt HUD models walk no stored DPS row: '..walked)
 check(p1.builds==p0.builds,'and build no DPS projection')
 check(s1.rebuilds==s0.rebuilds+20,'fixture: each preparation rebuilt the view model: '..(s1.rebuilds-s0.rebuilds))
 local model=Tables(Nexus.Panel._lastModel)
 local copied=(s1.copiedTables-s0.copiedTables)/20
 print('HUD_REUSE rebuild copiedTables/prep',copied,'model tables',model)
 check(copied<=2*model+8,'a rebuilt model costs at most two model copies: '..copied..' tables for a '..model..'-table model')
 Refresh(1)
end

-- 3. One authoritative DPS revision: the next preparation rebuilds once and
-- shows the new value; later ones reuse it.
do
 local p0=Projection()
 check(fx:Receive('Alpha','dummy',{dps=77777}),'fixture: Alpha records 77777 on the Dummy')
 local walked=Refresh(1)+Refresh(20)
 local shown=MatchesOracle('after the revision')
 check(Dps(shown.performance.dummy.global)==77777,'the new global Dummy value is shown: '..tostring(Dps(shown.performance.dummy.global)))
 check(Projection().builds==p0.builds+1,'the revision rebuilt the projection exactly once')
 check(walked>0,'control: that rebuild walked the stored rows')
end

-- 4. Another Echo set selects its own rows; the previous set never leaks.
do
 UseWishlist('Bravo set',fx.players[3].ordinary)
 Refresh(5)
 local shown=MatchesOracle('Bravo set')
 check(Dps(shown.performance.dummy.global)==57000 and Dps(shown.performance.lk.global)==61000,
  'the Bravo set shows Bravo\'s global rows')
 check(shown.performance.dummy.personal==nil and shown.performance.lk.personal==nil,
  'and no personal row: this character has none for that set')
 UseWishlist('Alpha set again',fx.players[2].ordinary)
 Refresh(5)
 shown=MatchesOracle('Alpha set again')
 check(Dps(shown.performance.dummy.global)==77777 and Dps(shown.performance.dummy.personal)==20000,
  'returning to the Alpha set shows Alpha\'s rows again')
end

-- 4b. The player summary names this character's build. Editing that build's
-- title changes the build library only (no DPS revision); the HUD follows.
do
 local D=Nexus.DpsCapture
 local info=D.GetPlayerInfo(UnitName('player'))
 check(info and info.buildId and info.title=='Leaderboard fixture build of PrototypeTester',
  'fixture: the player summary names this character\'s build')
 local record=L.Copy(Nexus.BuildCatalog.Get(info.buildId))
 record.title='Renamed own build';record.lastModified=(record.lastModified or 0)+500
 local dpsRevision=Nexus.Revisions.Get('DPS_CHANGED')
 local ok,why,ticket=Nexus.BuildCatalog.Put(record,{source='overlay'})
 for _=1,400 do
  if type(ticket)~='table' or ticket.state~='pending' then break end
  H.Advance(.05,.05)
 end
 check(ok==true or (type(ticket)=='table' and ticket.committed==true),'fixture: the title edit is committed: '..tostring(why))
 check(Nexus.Revisions.Get('DPS_CHANGED')==dpsRevision,'fixture: the edit announces no DPS revision')
 Refresh(3)
 local shown=MatchesOracle('after the title edit')
 check(shown.bestDps.info and shown.bestDps.info.title=='Renamed own build',
  'the HUD names the renamed build: '..tostring(shown.bestDps.info and shown.bestDps.info.title))
end

-- 4c. The projection key on its own, with the bound DPS payload unchanged.
-- (A committed catalog edit publishes a new bundle, and a different logged-in
-- character re-admits the root; both also replace the payload.) A projection
-- asked for another player's name is that player's; a build-library revision
-- alone makes the next projection a rebuild.
do
 local D=Nexus.DpsCapture
 local function Payload() return rawget(rawget(NexusDB,'authorityBundle'),'dpsCapture') end
 local echoes=Nexus.Panel._lastModel.progress.dpsEchoes
 local payload=Payload()
 local mine=D.GetHudProjection(UnitName('player'),echoes)
 local alpha=D.GetHudProjection('Alpha',echoes)
 check(Payload()==payload,'fixture: the bound DPS payload is unchanged')
 check(Same(alpha.bestDps,{dummy=D.GetCharacterBest('dummy','Alpha'),lk=D.GetCharacterBest('lk','Alpha'),
  info=D.GetPlayerInfo('Alpha')}) and Dps(alpha.bestDps.dummy)==77777,
  'a projection for Alpha holds Alpha\'s rows: '..tostring(Dps(alpha.bestDps.dummy)))
 check(Dps(D.GetHudProjection(UnitName('player'),echoes).bestDps.dummy)==Dps(mine.bestDps.dummy),
  'and the own projection is this character\'s again')
 local before=Projection().builds
 Nexus.Revisions.Advance(Nexus.Revisions.BUILD_LIBRARY_CHANGED,{scope='all',reason='hud_prepare_reuse'})
 check(Payload()==payload,'fixture: the bound DPS payload is still unchanged')
 Refresh(1)
 check(Projection().builds==before+1,'a build-library revision alone rebuilds the projection once')
 MatchesOracle('after a build-library revision')
end

-- 5. Another character: the character rows follow the player, never the cache.
do
 local unitName=UnitName
 UnitName=function() return 'Alpha','Ebonhold' end
 local ok,err=pcall(function()
  Refresh(3)
  -- Whatever the reads answer for this player (the oracle), the rows the
  -- HUD showed for PrototypeTester are not carried over.
  local shown=MatchesOracle('as Alpha')
  check(Dps(shown.bestDps.dummy)~=38000 and Dps(shown.bestDps.lk)~=39000,
   'as Alpha the previous character\'s best rows are not shown: '..tostring(Dps(shown.bestDps.dummy)))
 end)
 UnitName=unitName
 assert(ok,err)
 Refresh(3)
 local shown=MatchesOracle('back as PrototypeTester')
 check(Dps(shown.bestDps.dummy)==38000,'back as PrototypeTester the own rows are shown again')
end

-- 6. The retained projection is shared read-only state: preparations never
-- change it, and the panel holds separate copies.
do
 local D=Nexus.DpsCapture
 local echoes=Nexus.Panel._lastModel.progress.dpsEchoes
 local projection=D.GetHudProjection(UnitName('player'),echoes)
 local before=F.Serialize(projection)
 Refresh(10)
 check(D.GetHudProjection(UnitName('player'),echoes)==projection,'fixture: the same projection is retained')
 check(F.Serialize(projection)==before,'ten preparations leave the retained projection unchanged')
 local model=Nexus.Panel._lastModel
 check(model.bestDps.dummy~=projection.bestDps.dummy
  and model.progress.performance.dummy.global~=projection.performance.dummy.global,
  'the panel model holds its own copies')
end

-- 7. The DPS source is replaced with no DPS revision (another saved root).
-- The HUD follows the new source, never the retained projection.
do
 local original=NexusDB
 local revision=Nexus.Revisions.Get('DPS_CHANGED')
 local replaced={}
 for k,v in realPairs(original)do replaced[k]=v end
 local bundle={}
 for k,v in realPairs(original.authorityBundle)do bundle[k]=v end
 bundle.dpsCapture=L.Copy(original.authorityBundle.dpsCapture)
 local mine=bundle.dpsCapture.characterBest.dummy[F.OWNER]
 check(mine and mine.dps==38000,'fixture: the copied source holds this character\'s Dummy row')
 mine.dps=12345
 replaced.authorityBundle=bundle
 NexusDB=replaced
 local ok,err=pcall(function()
  Refresh(2)
  local shown=MatchesOracle('replaced source')
  check(Dps(shown.bestDps.dummy)~=38000,'the replaced source\'s row is not the retained one: '..tostring(Dps(shown.bestDps.dummy)))
  check(Nexus.Revisions.Get('DPS_CHANGED')==revision,'fixture: no DPS revision announced the replacement')
 end)
 NexusDB=original
 assert(ok,err)
 Refresh(2)
 local shown=MatchesOracle('original source again')
 check(Dps(shown.bestDps.dummy)==38000,'with the original source back its row is shown again')
end

------------------------------------------------------------------------
-- A protected profile (a newer settings format, #90): saved DPS rows stay
-- readable in the HUD, reuse works, and nothing is written.
------------------------------------------------------------------------
do
 fx=L.New({players=Players()})
 local db=AddPersonal(fx:Install(F.Database({version=2})),fx)
 db.settingsVersion=6
 H=F.Boot(db,function(h) h.playerLevel=60 end)
 check(Nexus.BuildCatalog.Status().readOnly==true,'fixture: the profile is kept read-only')
 if _G.NexusQuickStart and _G.NexusQuickStart:IsShown() then _G.NexusQuickStart:Hide();H.Advance(.2) end
 H.Board({{spellId=200001,quality=1},{spellId=200020,quality=0},{spellId=200021,quality=1}})
 H.Notify();H.Advance(1)
 for _=1,3 do Step() end
 local saved=F.Serialize(NexusDB)
 watched={}
 local p0=Projection()
 Refresh(1)
 local shown=MatchesOracle('protected profile')
 check(Dps(shown.bestDps.dummy)==38000 and Dps(shown.bestDps.lk)==39000,
  'the protected profile\'s saved DPS rows are shown')
 Refresh(20)
 local p1=Projection()
 check(p1.hits>=p0.hits+20,'and reused: hits +'..(p1.hits-p0.hits))
 check(F.Serialize(NexusDB)==saved,'HUD preparations write nothing into the protected saved root')
end

print('PASS HUD preparation reuse checks='..checks)
