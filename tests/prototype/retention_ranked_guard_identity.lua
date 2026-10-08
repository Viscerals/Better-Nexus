-- Defensive contract test for the ranked-retention publication guard: its
-- live-table half. A ranked run binds its guard to DPS_CHANGED AND to the
-- exact live dpsCapture table it copied. This test replaces that table with a
-- different one WITHOUT advancing DPS_CHANGED and requires the guard that
-- DataRetention actually installed to refuse, and the real publication path
-- to write nothing stale and to prepare the run again from the replacement.
--
-- Scope: no product path found performs this replacement. After bundle
-- occupancy only a catalog publication replaces the bundle's dpsCapture
-- table, and none can publish while the ranked commit is the only candidate
-- (the two raw writers, DpsCapture DB and LegacyDataMigration Begin, write
-- the legacy location before occupancy only). The replacement here is a
-- controlled rawset of the bundle's dpsCapture field; the catalog's own
-- source check (TokenDrifted) does not cover dpsCapture, so the guard is the
-- only protection on this path, and nothing else is disabled.
--
-- Real TOC boot, compaction, catalog, scheduler and retention owner;
-- single-slice pacing; synthetic data. The only instrument is a pass-through
-- observer on BuildCatalog.CommitMaintenance that keeps the guard function
-- DataRetention passes (arguments and results unchanged).
local T=dofile('tests/prototype/startup_support.lua')
T.SingleSlicePacing()
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Own(name) return name:lower()..'@ebonhold' end
local function Bundle() return rawget(NexusDB,'authorityBundle') or {} end
local function Lk() return ((rawget(Bundle(),'dpsCapture') or {}).characterBest or {}).lk or {} end
local function DpsRevision() return Nexus.Revisions.Get(Nexus.Revisions.DPS_CHANGED) end
local function DeepCopy(v,seen)
 if type(v)~='table' then return v end
 seen=seen or {};if seen[v] then return seen[v] end
 local out={};seen[v]=out
 for k,x in pairs(v)do out[DeepCopy(k,seen)]=DeepCopy(x,seen) end
 return out
end

-- 28 Lich King rows: Alpha 52000, Pat (the only PRIEST) and 26 MAGE fillers
-- 40001-40026. Policy: 25 per category, 1 per class. Alpha and fillers C-Z
-- are the top 25, Pat is kept by the class minimum; fillers A and B are
-- removed, so the ranked commit carries a DPS copy and a guard.
local players={
 {name='Alpha',class='MAGE',dps={lk=52000},locked=6},
 {name='Pat',class='PRIEST',dps={lk=10000}},
}
for i=1,26 do players[#players+1]={name='Filler'..string.char(64+i),class='MAGE',dps={lk=40000+i},build='missing',variant=100,locked=0} end
local fx=L.New({players=players})
local db=fx:Install(F.Database())
db.settings.communityRetentionEnabled=true
db.settings.communityRetentionTopPerCategory=25
db.settings.communityRetentionMinPerClassPerCategory=1
local H=F.Boot(db)
for i=1,20000 do
 local m=Bundle().dataCompaction or {}
 if i>10 and m.version and not m.inProgress and not Nexus.Scheduler.Pending('data-compaction') then break end
 H.Advance(.05,.05)
end
check(Nexus.DataRetention.Limits(NexusDB).enabled==true,'fixture: ranked retention is enabled')

local C=Nexus.BuildCatalog
local commit=C.CommitMaintenance
local commits={}
C.CommitMaintenance=function(handle,overrides,guard)
 local info=debug.getinfo(2,'S')
 local a,b,c=commit(handle,overrides,guard)
 if info and tostring(info.source):find('DataRetention',1,true) then
  commits[#commits+1]={guard=guard,dps=type(overrides)=='table' and overrides.dpsCapture or nil,
   first=a,why=b,ticket=type(c)=='table' and c or nil}
 end
 return a,b,c
end

check(Nexus.DataRetention.Request('test: ranked run')==true,'fixture: a ranked run is requested')
local before,replaced,refusal
local quiet=0
for _=1,20000 do
 local first=commits[1]
 if first and first.ticket and first.ticket.state=='pending' and not replaced then
  check(type(first.guard)=='function' and first.dps~=nil,'the pending ranked commit carries a DPS copy and the guard DataRetention installed')
  check(first.dps.characterBest.lk[Own('FillerA')]==nil and first.dps.characterBest.lk[Own('FillerB')]==nil,
   'fixture: the pending commit removes fillers A and B')
  -- Control: the unchanged source is permitted.
  check(first.guard()==true,'control: with the copied table and revision in place the installed guard permits the publication')
  before={revision=DpsRevision(),table=rawget(Bundle(),'dpsCapture'),bundle=rawget(NexusDB,'authorityBundle'),
   meta=rawget(Bundle(),'dataRetention'),overlay=rawget(Bundle(),'communityBuilds'),markers=rawget(Bundle(),'communityRetentionEvictions')}
  -- Controlled replacement: a different table with the same rows and one
  -- distinguishing top-level field; DPS_CHANGED is not advanced.
  local replacement=DeepCopy(before.table)
  replacement.identityContractProbe='replacement'
  rawset(Bundle(),'dpsCapture',replacement)
  replaced=replacement
  check(DpsRevision()==before.revision,'the replacement advanced no DPS revision')
  check(first.guard()==false,'the installed guard refuses the replaced table although the revision is unchanged')
 end
 if replaced and not refusal and first.ticket.state~='pending' then
  refusal={state=first.ticket.state,reason=first.ticket.reason,table=rawget(Bundle(),'dpsCapture'),
   bundle=rawget(NexusDB,'authorityBundle'),meta=rawget(Bundle(),'dataRetention'),
   overlay=rawget(Bundle(),'communityBuilds'),markers=rawget(Bundle(),'communityRetentionEvictions')}
 end
 local busy=Nexus.Scheduler.Pending('data-retention.enforce')
 for _,c in ipairs(commits)do if c.ticket and c.ticket.state=='pending' then busy=true end end
 if busy then quiet=0 else quiet=quiet+1 end
 if quiet>20 then break end
 H.Advance(.05,.05)
end
C.CommitMaintenance=commit
check(replaced and refusal,'the replacement was made inside the pending window, and the window ended')
check(refusal.state=='failed' and refusal.reason=='PUBLICATION_SOURCE_CHANGED',
 'the real publication is refused: '..tostring(refusal.state)..' '..tostring(refusal.reason))
check(refusal.table==replaced and refusal.bundle==before.bundle,'no stale DPS copy was published: the replacement table is still in place')
check(refusal.meta==before.meta and refusal.overlay==before.overlay and refusal.markers==before.markers,
 'no retention summary, page deletion or marker from the refused run')
check(#commits==2 and commits[2].first~=false and commits[2].guard and commits[2].ticket and commits[2].ticket.state=='committed',
 'the run was prepared again once, from the current table, and published ('..#commits..' commits)')
check(commits[2].dps.identityContractProbe=='replacement','the new copy was taken from the replacement table')

-- The published result: the replacement's content is kept and the unchanged
-- policy is applied (fillers A and B removed).
local function Published(tag)
 local dps=rawget(Bundle(),'dpsCapture') or {}
 check(dps.identityContractProbe=='replacement',tag..': the replacement table\'s content is kept')
 local lk,want=Lk(),{[Own('Alpha')]=52000,[Own('Pat')]=10000}
 for i=3,26 do want[Own('Filler'..string.char(64+i))]=40000+i end
 local extra,missing=0,0
 for owner in pairs(lk)do if not want[owner] then extra=extra+1 end end
 for owner,v in pairs(want)do if not(lk[owner] and lk[owner].dps==v) then missing=missing+1 end end
 check(extra==0 and missing==0,tag..': the Lich King rows are the policy result ('..extra..' extra, '..missing..' missing)')
 local public=Nexus.DpsCapture.GetCharacterBest('lk','Alpha',Own('Alpha'))
 check(public and public.dps==52000,tag..': the public read agrees')
end
Published('after the fresh run')
H=F.Reload()
Published('after reload')
print('PASS retention_ranked_guard_identity: the installed ranked guard refuses a replaced live dpsCapture table with an unchanged revision; nothing stale is published; the run is prepared again from the replacement (defensive contract, no product path found) checks='..checks)
