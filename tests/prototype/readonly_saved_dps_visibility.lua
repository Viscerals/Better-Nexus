-- Read-only is not unreadable. A saved profile this build keeps read-only
-- (future format, unverified format 5, malformed marker) still shows the DPS
-- records it has saved, from an existing authority bundle or from the saved
-- dpsCapture with no bundle, through the DPS lookups, the Leaderboard view and
-- the Build Library's default qualified view. Nothing is written into the
-- saved root and received records are still refused. A saved graph outside the
-- session copy bound is not shown. The saved error history is still listed.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Fx()
 return L.New({players={
  {name='Alpha',class='MAGE',dps={lk=52000,dummy=48000}},
  {name='Bravo',class='PRIEST',dps={lk=61000}},
  {name='PrototypeTester',class='MAGE',dps={lk=39000,dummy=38000},isLocal=true},
 }})
end
local function Load(text)return assert(loadstring('return '..text))()end

-- LEG: DPS rows at the saved dpsCapture, builds in communityBuilds, no bundle.
local LEG=F.Serialize(Fx():Install(F.Database({version=5})))
-- EB: the authority bundle a supported session of this build writes from the
-- same input, as saved at logout.
local EB
do
 local H=F.Boot(Fx():Install(F.Database({version=2})))
 for _=1,240 do H.Advance(.5,.5) end
 H.Fire('PLAYER_LOGOUT')
 EB=F.Serialize(NexusDB)
 local cb=Load(EB).authorityBundle.dpsCapture.characterBest
 check(cb.lk['alpha@ebonhold'].dps==52000,'SETUP: the saved bundle carries the DPS rows')
end

local function Board(cat)
 local rows=Nexus.DpsCapture.GetDpsBoard(cat);local out={}
 for i,r in ipairs(rows)do out[i]=tostring(r.player)..':'..tostring(r.dps)end
 return #rows,table.concat(out,';')
end
local function View(H,cat)
 local LB=Nexus.Leaderboard
 if LB.IsShown() then LB.SetCategory(cat) else LB.Show(cat) end
 local v,d
 for _=1,4000 do
  H.Advance(.05,.05)
  v,d=LB.VirtualStats(),LB.DiagnosticSnapshot()
  if v.dataReady and d.projectionCurrent and not d.projectionPending and v.category==cat then break end
 end
 return v.publishedRows,v.dataReady
end
local function Qualified(H)
 local P=Nexus.ViewProjections
 local filters={currentClassOnly=false,scope='all',sortMode='title',page=1}
 for _=1,4000 do
  local rows,summary=P.RequestBuilds(filters)
  if rows then return #rows,summary.qualifying end
  P.PumpBuilds();H.Advance(.05,.05)
 end
end

-- The verified control shows the reference values every read-only case must match.
local expected
local function Run(label,text,mutate,readOnly)
 local db=Load(text)
 if mutate then mutate(db) end
 local input=F.Serialize(db)
 local fx=Fx()
 local H=F.Boot(db)
 for _=1,240 do H.Advance(.5,.5) end
 local D=Nexus.DpsCapture
 check(Nexus.BuildCatalog.Status().readOnly==readOnly,label..': catalog read-only is '..tostring(readOnly))
 local lk,lkRows=Board('lk');local dummy=Board('dummy')
 local best=D.GetCharacterBest('lk','Alpha');local info=D.GetPlayerInfo('Alpha')
 local ident=D.GetLeaderboardForIdentity(fx.players[1].buildId,fx.players[1].fingerprint,nil,'lk')
 local viewLk=View(H,'lk');local viewDummy=View(H,'dummy')
 local builds,qualifying=Qualified(H)
 print('READONLY_DPS',label,'board',lk..'/'..dummy,lkRows,'view',tostring(viewLk)..'/'..tostring(viewDummy),
  'qualified',tostring(builds)..'/'..tostring(qualifying))
 local measured={lk=lk,lkRows=lkRows,dummy=dummy,viewLk=viewLk,viewDummy=viewDummy,builds=builds}
 if not expected then
  check(lk==3 and dummy==2 and viewLk==3 and viewDummy==2 and builds and builds>0,'CONTROL: rows are shown')
  expected=measured
 end
 for key,value in pairs(expected)do
  check(measured[key]==value,label..': '..key..' is '..tostring(measured[key])..' (expected '..tostring(value)..')')
 end
 check(best and best.dps==52000,label..': character best is read')
 check(info and info.dps==52000,label..': player info is read')
 check(#ident==1 and ident[1].dps==52000,label..': identity leaderboard is read')
 if readOnly then
  check(F.Serialize(NexusDB)==input,label..': reads and views write nothing')
 end
 local ok,accepted,why=pcall(fx.Receive,fx,'Alpha','lk',{dps=99000})
 for _=1,40 do H.Advance(.5,.5) end
 check(ok,label..': the receiver runs ('..tostring(accepted)..')')
 if readOnly then
  check(accepted==false and why=='storage',label..': a received record is refused ('..tostring(why)..')')
  check(D.GetCharacterBest('lk','Alpha').dps==52000,label..': the saved row stays after a refused record')
  H.Fire('PLAYER_LOGOUT')
  check(F.Serialize(NexusDB)==input,label..': the saved root is byte-identical after the session')
 else
  check(accepted==true and D.GetCharacterBest('lk','Alpha').dps==99000,label..': a writable profile accepts the record')
 end
end

Run('CTRL-EB-known5',EB,function(d)d.settingsVersion=5 end,false)
Run('CTRL-EB-supported2',EB,nil,false)
Run('CTRL-LEG-known5',LEG,nil,false)
Run('EB-future6',EB,function(d)d.settingsVersion=6 end,true)
Run('EB-unverified5',EB,function(d)d.settingsVersion=5;d.settings.syncMode='sometimes' end,true)
Run('EB-malformed6.5',EB,function(d)d.settingsVersion=6.5 end,true)
Run('LEG-future6',LEG,function(d)d.settingsVersion=6 end,true)
Run('LEG-unverified5',LEG,function(d)d.settings.syncMode='sometimes' end,true)
Run('LEG-malformed6.5',LEG,function(d)d.settingsVersion=6.5 end,true)

-- Outside the session copy bound (nesting deeper than 12): nothing is shown,
-- nothing is written, and the DPS debug log says why.
do
 local db=Load(EB);db.settingsVersion=6
 local deep={};local node=deep
 for _=1,13 do node.next={};node=node.next end
 db.authorityBundle.dpsCapture.characterBest.lk.deep=deep
 local input=F.Serialize(db)
 local H=F.Boot(db)
 for _=1,240 do H.Advance(.5,.5) end
 local lk=Board('lk')
 print('READONLY_DPS','EB-future6-over-bound','board',lk)
 check(lk==0,'over the copy bound: no saved row is shown')
 check(Nexus.DpsCapture.GetDebugLog():find('saved DPS records not shown',1,true),'over the copy bound: the DPS debug log says why')
 H.Fire('PLAYER_LOGOUT')
 check(F.Serialize(NexusDB)==input,'over the copy bound: the saved root is byte-identical')
end

-- A saved DPS key this build does not read does not stop the known rows.
do
 local db=Load(EB);db.settingsVersion=6
 db.authorityBundle.dpsCapture.futureOnly={marker='kept'}
 local input=F.Serialize(db)
 local H=F.Boot(db)
 for _=1,240 do H.Advance(.5,.5) end
 check(Board('lk')==3,'unknown saved DPS key: known rows are still shown')
 H.Fire('PLAYER_LOGOUT')
 check(F.Serialize(NexusDB)==input,'unknown saved DPS key: the saved root is byte-identical')
end

-- DPS reads create a missing root and convert the older per-player
-- leaderboard shape in the store they read. Both must happen in the session
-- copy, never in the saved tables. The converted older rows are shown, as a
-- writable profile shows them.
do
 local db=Load(EB);db.settingsVersion=6
 db.authorityBundle.dpsCapture.characterBest.dummy=nil
 local input=F.Serialize(db)
 local H=F.Boot(db)
 for _=1,240 do H.Advance(.5,.5) end
 local lk,dummy=Board('lk'),Board('dummy')
 print('READONLY_DPS','EB-future6-missing-root','board',lk..'/'..dummy)
 check(lk==3 and dummy==0,'missing saved root: the other rows are shown')
 check(F.Serialize(NexusDB)==input,'missing saved root: reads create nothing in the saved root')
 H.Fire('PLAYER_LOGOUT')
 check(F.Serialize(NexusDB)==input,'missing saved root: the saved root is byte-identical after the session')
end
do
 local fx=Fx()
 local db=F.Database({version=5})
 db.communityBuilds={}
 for _,id in ipairs(fx.buildOrder)do db.communityBuilds[id]=L.Copy(fx.builds[id]) end
 db.dpsCapture={leaderboard={}}
 for _,p in ipairs(fx.players)do
  for _,cat in ipairs({'lk','dummy'})do
   if p.dps[cat] then
    local byPlayer=db.dpsCapture.leaderboard[p.fingerprint] or {}
    db.dpsCapture.leaderboard[p.fingerprint]=byPlayer
    byPlayer[cat]=byPlayer[cat] or {}
    byPlayer[cat][p.name]={dps=p.dps[cat],ts=p.ts[cat],duration=p.duration[cat],level=80,class=p.class,
     realm=fx.realmKey,buildId=p.buildId,echoes=L.Copy(p.dpsOrdinary)}
   end
  end
 end
 db.settingsVersion=6
 local input=F.Serialize(db)
 local H=F.Boot(db)
 for _=1,240 do H.Advance(.5,.5) end
 local lk,dummy=Board('lk'),Board('dummy')
 View(H,'lk')
 print('READONLY_DPS','OLD-future6','board',lk..'/'..dummy)
 check(lk==3 and dummy==2,'older leaderboard shape: converted in the session copy and shown')
 check(F.Serialize(NexusDB)==input,'older leaderboard shape: reads convert nothing in the saved root')
 H.Fire('PLAYER_LOGOUT')
 check(F.Serialize(NexusDB)==input,'older leaderboard shape: the saved root is byte-identical after the session')
end

-- The saved error history is still listed in a read-only session.
for _,v in ipairs({6,5})do
 local db=F.Database({version=v,mutate=function(d)
  if v==5 then d.settings.syncMode='sometimes' end
  d.errorHistory={{timestamp='2026-09-01 10:00:00',source='saved-src',message='saved synthetic error one'},
   {timestamp='2026-09-01 10:01:00',source='saved-src',message='saved synthetic error two'}}
 end})
 local input=F.Serialize(db)
 local H=F.Boot(db)
 for _=1,20 do H.Advance(.5,.5) end
 check(Nexus.MainInternals.SavedRootReadOnlyV1()~=nil,'SETUP: format '..v..' profile is read-only')
 local history=Nexus.Errors.History()
 print('READONLY_ERRORS','format',v,'listed',#history)
 check(#history==2 and history[2].message=='saved synthetic error two','format '..v..': the saved error history is listed')
 H.Fire('PLAYER_LOGOUT')
 check(F.Serialize(NexusDB)==input,'format '..v..': the saved root is byte-identical')
end
print('PASS read-only saved profiles show their saved DPS records and error history and write nothing='..checks)
