-- The ranked retention scan walks the catalog summaries over many frames on
-- one summary cursor. Two other readers used to open an UNNAMED summary
-- cursor and so superseded that scan on the shared slot: the Sync diagnostic
-- page (/nexus log sync) and the hash cache's availability probe (every cold
-- start on a catalog above the one-call bound). Each fixed reader now owns
-- its own slot from a bounded allowlist; an unknown or unnamed caller keeps
-- the shared slot exactly as before. A catalog commit still ends a scan:
-- that is the root changing, not a reader. Real TOC boot, scheduler,
-- catalog, retention owner, hash cache and log viewer; synthetic data; the
-- local clock is a controlled time() for this test only.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local clock=1790000000
local function Clock(h) time=function() return clock+math.floor(h.now) end end
local function Record(id)
 return {id=id,title='Synthetic '..id,author='Peer'..id:gsub('%W','')..'-Realm',class='MAGE',postedAt=1,lastModified=1,
  ordinaryComplete=true,loadoutAvailable=true,lockedEchoes={},lockedComplete=true,
  echoes={{spellId=200001,quality=1,stacks=1},{spellId=200002,quality=2,stacks=1}}}
end
local function RankedDb(rows)
 local db={settingsVersion=5,accountCharacters={},settings={communityRetentionEnabled=true},chars={},communityBuilds={},
  communityRetentionEvictions={['legacy-1']=1700000000}}
 for i=1,rows do db.communityBuilds['b-'..i]=Record('b-'..i) end
 return db
end
-- Every summary cursor a product owner opens, by owner file and reader name.
local opened={}
local function HookCursor()
 local C=Nexus.BuildCatalog;local begin=C.BeginSummaryCursor
 C.BeginSummaryCursor=function(reader,...)
  -- The nearest Lua caller (a pcall frame in between is skipped).
  local owner='?'
  for level=2,8 do
   local info=debug.getinfo(level,'S');local source=tostring(info and info.source or '')
   local name=source:match('([%w_]+)%.lua')
   if name then owner=name;break end
  end
  opened[#opened+1]=owner..':'..tostring(reader)
  return begin(reader,...)
 end
end
F.fileHooks={[ [[core\BuildCatalog.lua]] ]=HookCursor}
local H=F.Boot(RankedDb(40),Clock)
F.fileHooks=nil
local C,R,Cache=Nexus.BuildCatalog,Nexus.DataRetention,Nexus.BuildHashCache
local function Run(seconds) for _=1,math.floor(seconds/.5) do H.Advance(.5,.5) end end
-- The retention owner's own result for a run is read from its Enforce
-- return value: a run that commits nothing does not rewrite the durable
-- `last` record, so that record would describe an earlier run.
local function Opened(owner) local out={} for _,row in ipairs(opened) do if row:find('^'..owner..':') then out[#out+1]=row end end return table.concat(out,' ') end
Run(120)
check(Cache.Stats().phase=='ready','fixture: the hash cache is warm after start-up')
local startup=opened;opened={}

-- A ranked run whose overlay scan meets `during` once while in progress.
local function RankedRun(reason,during)
 local seen,final=false,nil
 local enforce=R.Enforce
 R.Enforce=function(database,why)
  local result=enforce(database,why)
  if why==reason and type(result)=='table' then
   if result.pending==true and result.workDomain=='retention-overlay-scan' and not seen then
    seen=true;if during then during() end
   elseif result.pending~=true then
    final=result
   end
  end
  return result
 end
 check(R.Request(reason)==true,'fixture: a ranked run is requested: '..reason)
 Run(120)
 R.Enforce=enforce
 check(seen,'fixture: the scan was in progress: '..reason)
 check(type(final)=='table','fixture: the run finished: '..reason)
 return final or {}
end

-- 1. Control: an undisturbed ranked run completes its scan. (The start-up
-- run's scan is ended by start-up catalog maintenance commits, a separate
-- behaviour; a later request scans afresh. Two requests are allowed.)
local control
for attempt=1,2 do
 control=RankedRun('test: control run '..attempt)
 if control.overlayScanIncomplete==nil then break end
end
check(control.overlayScanIncomplete==nil,'fixture: an undisturbed ranked run completes its scan: '..tostring(control.overlayScanIncomplete))

-- 2. The Sync diagnostic page (its bounded summary walk) while a ranked scan
-- runs: the scan completes, because the page walks on its own slot.
opened={}
local last=RankedRun('test: scan meets diagnostic page',function()
 Nexus.LogViewer.Show('sync');H.Advance(.3,.05)
 check(NexusLogViewer and NexusLogViewer:IsShown(),'fixture: the Sync log page is shown')
 Nexus.LogViewer.Toggle()
end)
check(Opened('MainDiagnostics')~='','fixture: the diagnostic page walked the summaries: '..Opened('MainDiagnostics'))
check(last.overlayScanIncomplete==nil,'the ranked scan completes although the Sync log page walked the summaries during it: '..tostring(last.overlayScanIncomplete))
check(not Opened('MainDiagnostics'):find(':nil',1,true),'the diagnostic page walks on its named slot: '..Opened('MainDiagnostics'))

-- 3. The hash cache's cold probe and walk during a ranked scan: the scan
-- completes. A revision bus notice alone makes the cache cold; no catalog
-- commit follows it in this fixture (checked below), so the cursor slot is
-- the only possible interference.
opened={}
local commits=0
local Rev=Nexus.Revisions
local advance=Rev.Advance
Rev.Advance=function(event,detail)
 if event==Rev.BUILD_LIBRARY_CHANGED and not (type(detail)=='table' and detail.reason=='test cold hash cache') then commits=commits+1 end
 return advance(event,detail)
end
last=RankedRun('test: scan meets hash cache',function()
 check(Cache.Delta()~=nil,'fixture: the cache is warm before the notice')
 Rev.Advance(Rev.BUILD_LIBRARY_CHANGED,{scope='all',reason='test cold hash cache'})
 check(Cache.Delta()==nil,'fixture: the cache is cold and probes the catalog')
end)
Rev.Advance=advance
check(commits==0,'fixture: no catalog commit happened during that run: '..commits)
check(Opened('BuildHashCache')~='' and not Opened('BuildHashCache'):find(':nil',1,true),'every hash-cache cursor is its named slot: '..Opened('BuildHashCache'))
check(last.overlayScanIncomplete==nil,'the ranked scan completes although the hash cache probed and walked the catalog during it: '..tostring(last.overlayScanIncomplete))
check(Cache.Stats().phase=='ready','fixture: the hash cache is warm again')

-- 4. At start-up both owners used their own slots too.
opened=startup
check(Opened('BuildHashCache')~='' and not Opened('BuildHashCache'):find(':nil',1,true),'every hash-cache cursor at start-up is its named slot: '..Opened('BuildHashCache'))
check(Opened('DataRetention')~='' and not Opened('DataRetention'):find(':nil',1,true),'every retention cursor at start-up is its named slot: '..Opened('DataRetention'))
opened={}

-- 5. A commit during a ranked scan still ends it: the root changed.
last=RankedRun('test: scan meets a commit',function()
 local ok,why,ticket=C.Put(Record('late-1'),{source='sync'})
 if ok==nil and type(ticket)=='table' then for _=1,8000 do H.Advance(.05,.05);if ticket.state~='pending' then break end end end
 check(C.Get('late-1')~=nil,'fixture: the commit landed: '..tostring(why))
end)
check(last.overlayScanIncomplete~=nil,'a catalog commit during the scan still ends it (root change, not a reader): '..tostring(last.overlayScanIncomplete))

-- 6. Unnamed and unknown callers keep the shared slot: the newer cursor
-- supersedes the older one (whose token leaves the registry: "invalid
-- cursor"), and a fixed reader never supersedes them.
local shared=C.BeginSummaryCursor()
local unknown=C.BeginSummaryCursor('not-a-fixed-reader')
local _,_,err=C.SummaryCursorNext(shared)
check(err=='invalid cursor','an unknown reader name shares the unnamed slot: '..tostring(err))
local retention=C.BeginSummaryCursor('retention')
local diagnostic=C.BeginSummaryCursor('diagnostic')
local community=C.BeginSummaryCursor('community')
local hash=C.BeginSummaryCursor('build-hash-cache')
local _,_,err2=C.SummaryCursorNext(unknown)
check(err2==nil,'the fixed readers left the shared cursor alone: '..tostring(err2))
for name,token in pairs({retention=retention,diagnostic=diagnostic,community=community,['build-hash-cache']=hash}) do
 local _,_,e=C.SummaryCursorNext(token)
 check(e==nil,name..': each fixed reader keeps its own cursor: '..tostring(e))
end
local retention2=C.BeginSummaryCursor('retention')
local _,_,err3=C.SummaryCursorNext(retention)
local _,_,err4=C.SummaryCursorNext(retention2)
local _,_,err5=C.SummaryCursorNext(diagnostic)
check(err3=='invalid cursor' and err4==nil and err5==nil,'one slot per fixed reader: a second retention cursor supersedes the first only: '..tostring(err3)..'/'..tostring(err4)..'/'..tostring(err5))
print('PASS summary_cursor_named_readers checks='..checks)
