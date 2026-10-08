-- A DPS record accepted while another catalog transaction holds an open
-- evidence candidate must stay self-sufficient, and must not disturb that
-- transaction.
--
-- F8: after the first compaction, DpsCapture.ReferenceEvidence compacted a
-- received row into the open candidate: it interned the Echo arrays there and
-- removed the row's inline arrays. If that transaction is refused, fails or is
-- cancelled, its candidate is discarded, and the row keeps only a reference
-- to an entry that no longer exists.
-- M1 (review of the F8 commit): interning into that candidate at all is also
-- wrong once its publish plan is fixed (index and witness phases): the
-- published root then counts one evidence append more than the plan applied,
-- the next read finds the drift, and the catalog stays ROOT_INVALIDATED for
-- the session (received records refused, public reads empty; a reload
-- recovers). This happened in the shipped (unlimited) mode too.
-- Now a record written under an open candidate binds its key and keeps its
-- inline arrays, exactly as outside a candidate, and is never interned into
-- another transaction's candidate.
--
-- Real TOC boot, compaction, retention, catalog and DpsCapture.ReceiveRecord;
-- single-slice pacing; synthetic data. The pending windows are unguarded
-- retention commits (a ranked run that removes no DPS row; a default-mode
-- run), so this test does not depend on the ranked publication guard.
local T=dofile('tests/prototype/startup_support.lua')
T.SingleSlicePacing()
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,fx,target
local function Own(name) return name:lower()..'@ebonhold' end
local function Lk() return ((rawget(rawget(NexusDB,'authorityBundle') or {},'dpsCapture') or {}).characterBest or {}).lk or {} end
local function Player(name) for _,p in ipairs(fx.players)do if p.name==name then return p end end end
local function List(rows)
 local out={}
 for _,r in ipairs(rows or {})do out[#out+1]=tostring(r.spellId)..':'..tostring(r.count or r.stacks) end
 return table.concat(out,',')
end

-- 25 Lich King rows (Alpha, Lowell, Pat and 22 fillers): a ranked run removes
-- nothing. Kilo has a build and no record yet (known-zero locked).
local function Boot(ranked)
 local players={
  {name='Alpha',class='MAGE',dps={lk=52000},locked=6},
  {name='Kilo',class='MAGE',locked=0},
  {name='Lowell',class='MAGE',dps={lk=30001},locked=3},
  {name='Pat',class='PRIEST',dps={lk=10000}},
 }
 for i=1,22 do players[#players+1]={name='Filler'..string.char(64+i),class='MAGE',dps={lk=40000+i},build='missing',variant=100,locked=0} end
 fx=L.New({players=players})
 local db=fx:Install(F.Database())
 if ranked then
  db.settings.communityRetentionEnabled=true
  db.settings.communityRetentionTopPerCategory=25
  db.settings.communityRetentionMinPerClassPerCategory=1
 end
 H=F.Boot(db)
 for i=1,20000 do
  local m=(NexusDB.authorityBundle or {}).dataCompaction or {}
  if i>10 and m.version and not m.inProgress and not Nexus.Scheduler.Pending('data-compaction') then break end
  H.Advance(.05,.05)
 end
 check(Nexus.DataCompaction.Enabled(NexusDB),'fixture: the first compaction is complete (reference storage is enabled)')
 check(Nexus.DataRetention.Limits(NexusDB).enabled==(ranked==true),'fixture: retention mode')
 -- The default mode repeats its full run only after 300 s.
 if not ranked then for _=1,310 do H.Advance(1,1) end end
 target=nil
 local C=Nexus.BuildCatalog
 local commit=C.CommitMaintenance
 C.CommitMaintenance=function(handle,overrides,guard)
  local info=debug.getinfo(2,'S')
  local a,b,c=commit(handle,overrides,guard)
  if info and tostring(info.source):find('DataRetention',1,true) and type(c)=='table' and not target then
   target={ticket=c,dps=type(overrides)=='table' and overrides.dpsCapture~=nil,guarded=guard~=nil,offset=-1}
  end
  return a,b,c
 end
end

-- Request a retention run; at the k-th pending frame of its commit, run
-- fn(). Every frame the catalog must not be invalidated. Returns the window
-- length and whether fn ran inside it.
local function Window(k,fn,tag)
 check(Nexus.DataRetention.Request('test: retention run')==true,tag..': a retention run is requested')
 local fired,invalid
 for _=1,8000 do
  if target and target.ticket.state=='pending' then
   target.offset=target.offset+1
   if k and target.offset==k and not fired then
    check(Nexus.LoadoutEvidence.CandidateOpen(),tag..': the retention transaction holds an open evidence candidate at the write')
    fn()
    fired=target.ticket.state=='pending'
   end
  end
  local s=Nexus.BuildCatalog.Status()
  if s.state=='ROOT_INVALIDATED' and not invalid then invalid=tostring(s.reason) end
  if target and target.ticket.state~='pending' and not Nexus.Scheduler.Pending('data-retention.enforce') then break end
  H.Advance(.05,.05)
 end
 check(target and target.ticket.state=='committed',tag..': the retention commit published: '..tostring(target and target.ticket.state))
 check(not target.dps and not target.guarded,tag..': the pending commit is unguarded and carries no DPS copy')
 check(invalid==nil,tag..': the catalog is never invalidated ('..tostring(invalid)..')')
 return target.offset+1,fired
end

local function Exact(tag,names)
 for _,name in ipairs(names)do
  local q=Player(name)
  local public=Nexus.DpsCapture.GetCharacterBest('lk',q.name,q.owner)
  check(public and public.dps==q.dps.lk and List(public.echoes)==List(q.dpsOrdinary) and List(public.lockedEchoes)==List(q.dpsLocked),
   tag..': '..name..' resolves its exact ordinary and locked evidence')
 end
 check(Nexus.BuildCatalog.Get(Player('Alpha').buildId)~=nil,tag..': the catalog serves builds')
end

------------------------------------------------------------------------
-- 1. F8: records accepted in the window keep their inline arrays while the
-- candidate is open, and resolve after the commit and after a reload.
------------------------------------------------------------------------
Boot(true)
local _,fired=Window(0,function()
 check(fx:Receive('Kilo','lk',{dps=60000,ts=L.STAMP+300})==true,'a new record (known-zero locked) is accepted')
 check(fx:Receive('Lowell','lk',{dps=59000,ts=L.STAMP+301})==true,'an improved record (explicit locked) is accepted')
 for _,name in ipairs({'Kilo','Lowell'})do
  local q,row=Player(name),Lk()[Own(name)]
  check(row and type(row.echoes)=='table' and next(row.echoes)~=nil and type(row.evidenceKey)=='string',
   name..': while the candidate is open the stored row keeps its inline Echoes and binds its key')
  check(List(row.echoes)==List(q.dpsOrdinary),name..': the inline Echoes are the exact record')
  if q.dpsLocked then check(List(row.lockedEchoes)==List(q.dpsLocked),name..': the inline locked Echoes are kept') end
 end
end,'inline')
check(fired,'inline: the writes landed while the commit was pending')
Exact('after the commit',{'Kilo','Lowell'})
H=F.Reload()
Exact('after reload',{'Kilo','Lowell'})
check(fx:Receive('Kilo','lk',{dps=61000,ts=L.STAMP+310})==true,'a later Kilo record is accepted outside a candidate')
Exact('the later record',{'Kilo'})

------------------------------------------------------------------------
-- 2-3. M1: a new record at every offset of an unguarded pending retention
-- commit (ranked run that removes nothing; default mode) leaves the catalog
-- admitted, and the record resolves after the commit and after a reload.
------------------------------------------------------------------------
local summary={}
for _,mode in ipairs({{true,'ranked'},{false,'default'}})do
 Boot(mode[1])
 local W=Window(nil,nil,mode[2]..' discovery')
 check(W>=5,mode[2]..': the pending window lasts '..W..' frames')
 local landed=0
 for k=0,W-1 do
  Boot(mode[1])
  local length,inside=Window(k,function()
   check(fx:Receive('Kilo','lk',{dps=60000,ts=L.STAMP+300})==true,mode[2]..' +'..k..': Kilo is accepted')
  end,mode[2]..' +'..k)
  check(inside and length==W,mode[2]..' +'..k..': the write landed inside the window ('..length..'/'..W..' frames)')
  landed=landed+1
  Exact(mode[2]..' +'..k,{'Kilo'})
  if k==W-1 then H=F.Reload();Exact(mode[2]..' +'..k..' after reload',{'Kilo'}) end
 end
 check(landed==W,mode[2]..': every offset of the window was exercised ('..landed..'/'..W..')')
 summary[#summary+1]=mode[2]..' W='..W
end
print('PASS dps_evidence_open_candidate: a record accepted under another transaction\'s open candidate keeps its inline evidence and never drifts that transaction ['..table.concat(summary,' ')..'] checks='..checks)
