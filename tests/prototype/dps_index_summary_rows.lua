-- The DPS identity index builds the Community eligibility (one character's
-- real Dummy + Lich King pair per loadout) from projected rows. Those rows
-- used to be a full deep copy of every stored row; they are now the stored
-- row's fields with its Echo lists in the stored shape, because the pair
-- summary only reads them and keeps none. The result must be exactly the
-- reference summary computed from deep copies, no stored row may be touched
-- by a rebuild, and a record handed to a caller must not alias stored
-- tables. Real TOC boot, synthetic leaderboard players.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local players={{name='PrototypeTester',class='MAGE',isLocal=true,variant=30,ordinary=60}}
for i=1,24 do players[#players+1]={name='Player'..i,class='MAGE',variant=1+(i%6),dps={dummy=30000+i*7,lk=31000+i*5}} end
players[#players+1]={name='Dummyonly',class='MAGE',variant=9,dps={dummy=41000}}
players[#players+1]={name='Lkonly',class='MAGE',variant=9,dps={lk=42000}}
local fx=L.New({players=players})
local H=F.Boot(fx:Install(F.Database({version=2})),function(h) h.playerLevel=60 end)
for _=1,400 do H.Advance(.05,.05) end
local D,E=Nexus.DpsCapture,Nexus.CandidateEvidence
local store=rawget(NexusDB.authorityBundle,'dpsCapture').characterBest
local function DeepCopy(value,seen)
 if type(value)~='table' then return value end
 seen=seen or {};if seen[value] then return seen[value] end
 local copy={};seen[value]=copy
 for k,v in pairs(value) do copy[DeepCopy(k,seen)]=DeepCopy(v,seen) end
 return copy
end
-- Snapshot of every stored row's own Echo tables, by identity.
local before={}
for _,category in ipairs({'dummy','lk'}) do
 for key,row in pairs(store[category] or {}) do before[category..'/'..key]={echoes=row.echoes,locked=row.lockedEchoes,copy=DeepCopy(row)} end
end
-- 1. The eligibility the index publishes equals the reference built from
-- deep copies through the same pair summary.
local eligibility=D.GetCommunityEligibility()
local rowsByFingerprint={dummy={},lk={}}
for _,category in ipairs({'dummy','lk'}) do
 for _,row in pairs(store[category] or {}) do
  if D.IsDurationEligible(category,row.duration) and type(row.fingerprint)=='string' and (tonumber(row.dps) or 0)>0 then
   local projected=DeepCopy(row)
   local resolved=D.MaterializeRecord(row)
   projected.echoes=resolved and resolved.echoes or projected.echoes
   projected.lockedEchoes=resolved and resolved.lockedEchoes or projected.lockedEchoes or {}
   local list=rowsByFingerprint[category][row.fingerprint] or {};list[#list+1]=projected
   rowsByFingerprint[category][row.fingerprint]=list
  end
 end
end
local expected,count=0,0
for fingerprint,dummyRows in pairs(rowsByFingerprint.dummy) do
 local lkRows=rowsByFingerprint.lk[fingerprint]
 local summary=lkRows and E.DpsSummary(dummyRows,lkRows) or nil
 if summary and summary.average>0 then
  expected=expected+1
  local got=eligibility[fingerprint]
  check(type(got)=='table','a qualifying loadout is in the eligibility: '..fingerprint)
  for _,field in ipairs({'dummy','lk','average','count','best'}) do
   check(got[field]==summary[field],fingerprint..' '..field..': '..tostring(got[field])..' == '..tostring(summary[field]))
  end
  check(got.pair==nil,'the published summary keeps no pair rows')
 end
end
for fingerprint in pairs(eligibility) do count=count+1 end
-- The 24 paired players share six loadout variants.
check(count==expected and expected==6,'exactly the qualifying loadouts are listed: '..count..' of '..expected)
local lone
for _,row in pairs(store.dummy) do if tonumber(row.dps)==41000 then lone=row end end
check(lone~=nil and type(lone.fingerprint)=='string' and eligibility[lone.fingerprint]==nil,'a Dummy-only and a Lich-King-only character on one loadout do not qualify')
-- 2. The rebuild touched no stored row.
for key,snapshot in pairs(before) do
 local category,rowKey=key:match('^(%a+)/(.+)$')
 local row=store[category][rowKey]
 check(row.echoes==snapshot.echoes and row.lockedEchoes==snapshot.locked,'stored row tables are the same objects: '..key)
 local function Equal(a,b,seen)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  seen=seen or {};if seen[a] then return seen[a]==b end;seen[a]=b
  for k,v in pairs(a) do if not Equal(v,b[k],seen) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
 end
 check(Equal(row,snapshot.copy),'stored row content is unchanged: '..key)
end
-- 3. A record handed to a caller does not alias the stored tables.
local sample
for _,row in pairs(store.dummy) do if type(row.fingerprint)=='string' then sample=row;break end end
local record=D.GetRecordForIdentity(sample.buildId,sample.fingerprint,sample.loadoutHash,'dummy')
check(type(record)=='table' and record.echoes~=sample.echoes and record.lockedEchoes~=sample.lockedEchoes,'a caller record is its own copy')
print('PASS dps_index_summary_rows checks='..checks)
