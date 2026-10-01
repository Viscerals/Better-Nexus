-- Catalog verdict reuse (BN-CATALOG-VERDICT-REUSE-006): an ordinary Put or
-- PutBatch mutation re-admitted every catalog row, although it changes only
-- its own rows. Required: after the first Put following an admission, a
-- mutation walks only its own rows and the rows that cannot be proven
-- unchanged (evidence-pool readers, removal or retention markers); every
-- other verdict is reused. Work is measured by the mutation's own work
-- counters (`rows` is charged once per walked row and once per row in
-- finalisation) and by the catalog's debug statistics.
-- Real TOC boot, real catalog; synthetic records only. Single-slice pacing
-- (no profile clock) keeps the slice boundaries deterministic.
dofile('tests/prototype/startup_support.lua').SingleSlicePacing()
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local clock=1790000000
local function Clock() time=function() return clock end end
local function Record(id,extra)
 local r={id=id,title='Synthetic '..tostring(id),author='Peer-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}}
 for k,v in pairs(extra or {})do r[k]=v end
 return r
end
local H,C,ST
local lastHandle,onRows
local function Boot(count)
 local db={settingsVersion=5,accountCharacters={},settings={},chars={},communityBuilds={}}
 for i=1,count do db.communityBuilds['b-'..i]=Record('b-'..i,{lastModified=i}) end
 H=F.Boot(db,Clock)
 C=Nexus.BuildCatalog
 ST=nil
 for i=1,255 do local n,v=debug.getupvalue(C.DebugStats,i);if not n then break end;if n=='ST' then ST=v end end
 assert(ST,'catalog state')
 local pump=C.PumpRootAdmission
 C.PumpRootAdmission=function(...)
  if ST.candidate then lastHandle=ST.candidate end
  if onRows and ST.candidate and ST.candidate.phase=='rows' then local f=onRows;onRows=nil;f() end
  return pump(...)
 end
 for _=1,200 do H.Advance(.05,.05) end
 check(Nexus.StartupStatus().state=='ready' and C.Count()==count,'fixture: '..count..' builds admitted')
end
local function Settle(ok,why,tickets)
 if ok==nil and type(tickets)=='table' then
  for _=1,20000 do
   H.Advance(.05,.05)
   local open=false
   for _,t in ipairs(tickets) do if t.state=='pending' then open=true end end
   if not open then break end
  end
  local all=true
  for _,t in ipairs(tickets) do if not t.committed then all=false end end
  return all
 end
 return ok
end
local serial=0
-- One PutBatch of `n` new builds (or the given records); returns the number
-- of rows the mutation walked and the debug statistics after it.
local function Batch(n,records)
 lastHandle=nil
 local requests={}
 if records then
  for i,r in ipairs(records) do requests[i]={record=r,options={}} end
 else
  for i=1,n do serial=serial+1;requests[i]={record=Record('new-'..serial,{lastModified=100+serial}),options={}} end
 end
 local ok,why,tickets=C.PutBatch(requests)
 check(Settle(ok,why,tickets),'the batch commits: '..tostring(why))
 local h=assert(lastHandle,'mutation handle observed')
 local walked=h.counters.totals.rows-h.slotCount
 return walked,h.slotCount,C.DebugStats()
end

-- 1. The first Put after the start-up admission walks every row (its root
-- is not a reuse source).
Boot(40)
local walked,slots=Batch(1)
check(slots==41 and walked==41,'the first batch after admission walks every row: '..walked..'/'..slots)
-- 2. The next one-row batch walks only its own row.
walked,slots=Batch(1)
check(slots==42 and walked==1,'a later one-row batch walks only its own row: '..walked..'/'..slots)
local stats=C.DebugStats()
check((stats.verdictReuses or 0)>=41 and (stats.rowWalks or 0)>=1,'the reuse is counted: reuses='..tostring(stats.verdictReuses)..' walks='..tostring(stats.rowWalks))
-- 3. An eight-row batch walks its eight rows.
walked,slots=Batch(8)
check(slots==50 and walked==8,'an eight-row batch walks only its eight rows: '..walked..'/'..slots)
-- 4. An update of an existing build walks only that build.
walked,slots=Batch(nil,{Record('b-7',{lastModified=500,title='Changed b-7'})})
check(slots==50 and walked==1,'an update walks only the updated row: '..walked..'/'..slots)
check(C.Get('b-7') and C.Get('b-7').title=='Changed b-7','the update is published')
-- 5. A row the previous mutation readmitted (the b-7 update) is walked by
-- the next one. A verdict walked while the evidence owner failed is not
-- reusable either: the batch after it walks those rows again.
local evidence=Nexus.LoadoutEvidence
local real=evidence.PublicOrdinaryCompleteness
onRows=function() evidence.PublicOrdinaryCompleteness=function() error('injected evidence failure') end end
walked,slots=Batch(1)
evidence.PublicOrdinaryCompleteness=real
check(slots==51 and walked==2,'the batch after an update walks its own row and the readmitted one: '..walked..'/'..slots)
walked,slots=Batch(1)
check(slots==52 and walked==3,'the next batch also walks both rows walked while the owner failed: '..walked..'/'..slots)
walked,slots=Batch(1)
check(slots==53 and walked==1,'after that only its own row: '..walked..'/'..slots)
print('PASS catalog verdict reuse checks='..checks)
