-- A DPS record accepted while a catalog transaction holds an open evidence
-- candidate must stay self-sufficient until its evidence entry is durable.
--
-- Cause: after the first compaction, DpsCapture.ReferenceEvidence compacted
-- a received row into the open candidate: it interned the Echo arrays there
-- and removed the row's inline arrays. The candidate belongs to another
-- transaction (here a pending ranked-retention commit). If that transaction
-- is refused, fails or is cancelled, its candidate is discarded with it, and
-- the stored row keeps only a reference to an entry that no longer exists.
-- Now, while a candidate is open, the entries are still staged in it (a
-- publication carries them), but the inline arrays are kept; the existing
-- rule outside a candidate drops them once the entry is durable.
--
-- Real TOC boot, compaction, ranked retention, catalog and
-- DpsCapture.ReceiveRecord; single-slice pacing; synthetic data. The pending
-- window is a ranked run that removes no DPS row (25 Lich King rows), so this
-- test does not depend on the ranked publication guard.
local T=dofile('tests/prototype/startup_support.lua')
T.SingleSlicePacing()
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,fx
local function Own(name) return name:lower()..'@ebonhold' end
local function Lk() return ((rawget(rawget(NexusDB,'authorityBundle') or {},'dpsCapture') or {}).characterBest or {}).lk or {} end
local function Player(name) for _,p in ipairs(fx.players)do if p.name==name then return p end end end
local function List(rows)
 local out={}
 for _,r in ipairs(rows or {})do out[#out+1]=tostring(r.spellId)..':'..tostring(r.count or r.stacks) end
 return table.concat(out,',')
end

local players={
 {name='Alpha',class='MAGE',dps={lk=52000},locked=6},
 {name='Kilo',class='MAGE',locked=0},
 {name='Lowell',class='MAGE',dps={lk=30001},locked=3},
 {name='Pat',class='PRIEST',dps={lk=10000}},
}
for i=1,22 do players[#players+1]={name='Filler'..string.char(64+i),class='MAGE',dps={lk=40000+i},build='missing',variant=100,locked=0} end
fx=L.New({players=players})
local db=fx:Install(F.Database())
db.settings.communityRetentionEnabled=true
db.settings.communityRetentionTopPerCategory=25
db.settings.communityRetentionMinPerClassPerCategory=1
H=F.Boot(db)
for i=1,20000 do
 local m=(NexusDB.authorityBundle or {}).dataCompaction or {}
 if i>10 and m.version and not m.inProgress and not Nexus.Scheduler.Pending('data-compaction') then break end
 H.Advance(.05,.05)
end
check(Nexus.DataCompaction.Enabled(NexusDB),'fixture: the first compaction is complete (reference storage is enabled)')

-- Observe (pass through) the ranked retention commit to find its window.
local C=Nexus.BuildCatalog
local commit=C.CommitMaintenance
local target
C.CommitMaintenance=function(handle,overrides,guard)
 local info=debug.getinfo(2,'S')
 local a,b,c=commit(handle,overrides,guard)
 if info and tostring(info.source):find('DataRetention',1,true) and type(c)=='table' and not target then
  target={ticket=c,dps=type(overrides)=='table' and overrides.dpsCapture~=nil}
 end
 return a,b,c
end
check(Nexus.DataRetention.Request('test: ranked run')==true,'fixture: a ranked run is requested')
local wrote,after
for _=1,6000 do
 if target and target.ticket.state=='pending' and not wrote then
  check(Nexus.LoadoutEvidence.CandidateOpen(),'the retention transaction holds an open evidence candidate at the write')
  check(not target.dps,'fixture: the pending ranked commit removes no DPS row')
  local p=Player('Kilo')
  check(fx:Receive('Kilo','lk',{dps=60000,ts=L.STAMP+300})==true,'a new record (known-zero locked) is accepted')
  check(fx:Receive('Lowell','lk',{dps=59000,ts=L.STAMP+301})==true,'an improved record (explicit locked) is accepted')
  wrote=true
  check(target.ticket.state=='pending' and Nexus.LoadoutEvidence.CandidateOpen(),'the writes landed while the candidate was open')
  for _,name in ipairs({'Kilo','Lowell'})do
   local q,row=Player(name),Lk()[Own(name)]
   check(row and type(row.echoes)=='table' and next(row.echoes)~=nil and type(row.evidenceKey)=='string',
    name..': while the candidate is open the stored row keeps its inline Echoes and binds its key')
   check(List(row.echoes)==List(q.dpsOrdinary),name..': the inline Echoes are the exact record')
   if q.dpsLocked then check(List(row.lockedEchoes)==List(q.dpsLocked),name..': the inline locked Echoes are kept') end
  end
 end
 if wrote and target.ticket.state~='pending' and not after then after=target.ticket.state end
 if after and not Nexus.Scheduler.Pending('data-retention.enforce') then break end
 H.Advance(.05,.05)
end
C.CommitMaintenance=commit
check(wrote and after=='committed','the retention commit published after the writes: '..tostring(after))
local function Exact(tag)
 for _,name in ipairs({'Kilo','Lowell'})do
  local q=Player(name)
  local public=Nexus.DpsCapture.GetCharacterBest('lk',q.name,q.owner)
  check(public and public.dps==q.dps.lk and List(public.echoes)==List(q.dpsOrdinary) and List(public.lockedEchoes)==List(q.dpsLocked),
   tag..': '..name..' resolves its exact ordinary and locked evidence')
 end
end
Exact('after the commit')
H=F.Reload()
Exact('after reload')
-- Outside a candidate the existing rule drops inline arrays once the entry is
-- durable: Kilo's next record reuses the published entry.
check(not Nexus.LoadoutEvidence.CandidateOpen(),'fixture: no candidate is open')
check(fx:Receive('Kilo','lk',{dps=61000,ts=L.STAMP+310})==true,'a later Kilo record is accepted outside a candidate')
local row=Lk()[Own('Kilo')]
check(row and row.echoes==nil and type(row.evidenceKey)=='string','the later record is stored as a reference to the durable entry')
Exact('the later record')
print('PASS dps_evidence_open_candidate: a record accepted under an open candidate keeps its inline evidence until the entry is durable checks='..checks)
