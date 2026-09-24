-- Opt-in ranked retention must not publish its older dpsCapture snapshot over
-- a DPS record accepted while its commit is pending, and must still remove
-- what the unchanged ranked policy removes from the current rows.
--
-- Cause: a ranked run (settings.communityRetentionEnabled) deep-copies
-- dpsCapture, selects and trims rows, and commits the copy as a bundle
-- override. A DPS write accepted into the live store while that commit was
-- pending was replaced at publication (a new record removed, an improved
-- record reverted or removed). The same snapshot decides which auto pages
-- are orphaned, so a page that a new record references could be evicted.
-- Now the ranked transaction passes the catalog publication guard bound to
-- DPS_CHANGED and the live dpsCapture value it copied, whenever it publishes
-- decisions derived from that copy (DPS removals or overlay evictions). A
-- refused publication (PUBLICATION_SOURCE_CHANGED) writes nothing and is
-- prepared again from the current rows through the existing bounded retry
-- (the busy chain: same delays, same limit). A record accepted in the window
-- keeps its inline evidence while the refused transaction's candidate is
-- discarded (dps_evidence_open_candidate).
--
-- Policy in these fixtures: Lich King only (plus one Dummy row), 25 per
-- category, at least 1 per class. Real TOC boot, compaction, catalog,
-- scheduler, retention owner and DpsCapture.ReceiveRecord; single-slice
-- pacing. The only instruments are pass-through observers on
-- CommitMaintenance and Retention.Enforce. Synthetic data only.
local T=dofile('tests/prototype/startup_support.lua')
T.SingleSlicePacing()
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,fx,commits,results
local frame=0
local beforeCommit
local function Own(name) return name:lower()..'@ebonhold' end
local function Bundle() return rawget(NexusDB,'authorityBundle') or {} end
local function Dps() return rawget(Bundle(),'dpsCapture') or {} end
local function Lk() return (Dps().characterBest or {}).lk or {} end
local function Player(name) for _,p in ipairs(fx.players)do if p.name==name then return p end end end
local function Step(n) for _=1,n or 1 do H.Advance(.05,.05);frame=frame+1 end end
local function List(rows)
 local out={}
 for _,r in ipairs(rows or {})do out[#out+1]=tostring(r.spellId)..':'..tostring(r.count or r.stacks) end
 return table.concat(out,',')
end
local function Names(set)
 local out={};for k in pairs(set)do out[#out+1]=k end;table.sort(out);return table.concat(out,' ')
end

-- Alpha 52000 (explicit locked) also has a Dummy record; Kilo and November
-- have a build and no record yet (Kilo known-zero locked, November explicit
-- locked); Lowell 30001 and Lowry 30002 are the weakest MAGE records; Pat is
-- the only PRIEST (kept by the class minimum); Quinn has no build page; 26
-- MAGE fillers 40001-40026 without build pages share one loadout.
local function Players(opts)
 local players={}
 if not opts.fillersOnly then
  players={
   {name='Alpha',class='MAGE',dps={lk=52000,dummy=48000},locked=6},
   {name='Kilo',class='MAGE',locked=0},
   {name='Lowell',class='MAGE',dps={lk=30001},locked=3},
   {name='Lowry',class='MAGE',dps={lk=30002}},
   {name='November',class='MAGE',locked=2},
   {name='Pat',class='PRIEST',dps={lk=10000}},
   {name='Quinn',class='MAGE',locked=1,build='missing'},
  }
  if opts.orphan then players[#players+1]={name='Oscar',class='HUNTER',locked=0} end
 end
 for i=1,opts.fillers or 26 do
  players[#players+1]={name='Filler'..string.char(64+i),class='MAGE',dps={lk=40000+i},build='missing',variant=100,locked=0}
 end
 return players
end

local function Observe()
 local C,R=Nexus.BuildCatalog,Nexus.DataRetention
 local commit,enforce=C.CommitMaintenance,R.Enforce
 commits,results={},{}
 C.CommitMaintenance=function(handle,overrides,guard)
  local info=debug.getinfo(2,'S')
  local rec
  if info and tostring(info.source):find('DataRetention',1,true) then
   local o=type(overrides)=='table' and overrides or {}
   rec={frame=frame,dps=o.dpsCapture,meta=o.dataRetention,guarded=guard~=nil}
   commits[#commits+1]=rec
   if beforeCommit then local f=beforeCommit;beforeCommit=nil;f(rec) end
  end
  local a,b,c=commit(handle,overrides,guard)
  if rec then rec.first,rec.why,rec.ticket=a,b,type(c)=='table' and c or nil end
  return a,b,c
 end
 R.Enforce=function(database,reason)
  local r=enforce(database,reason)
  results[#results+1]={frame=frame,reason=reason,result=r}
  return r
 end
end

local function Boot(opts)
 opts=opts or {}
 fx=L.New({players=Players(opts),retentionMarkers=opts.markers,extraBuilds=opts.extraBuilds})
 local db=fx:Install(F.Database())
 db.settings.communityRetentionEnabled=true
 db.settings.communityRetentionTopPerCategory=25
 db.settings.communityRetentionMinPerClassPerCategory=1
 if opts.orphan then db.communityBuilds[Player('Oscar').buildId].autoDps=true end
 H=F.Boot(db);frame=0
 for i=1,20000 do
  local m=Bundle().dataCompaction or {}
  if i>10 and m.version and not m.inProgress and not Nexus.Scheduler.Pending('data-compaction') then
   check(Nexus.DataRetention.Limits(NexusDB).enabled==true,'fixture: ranked retention is enabled')
   Observe()
   return
  end
  Step(1)
 end
 error('fixture: the first compaction did not complete')
end

-- Request one ranked run and drive it (and its retries) to rest. inject:
-- {{window=k, offset=o, fn=...}}: fn runs at the o-th frame during which the
-- k-th retention commit that has a ticket is pending. perFrame(ctx) runs
-- every frame. Every injection must reach its window; every window must end.
local function Drive(inject,perFrame,limit)
 local ctx={windows={},byCommit={},fired=0}
 check(Nexus.DataRetention.Request('test: ranked run')==true,'fixture: a ranked run is requested')
 local quiet=0
 for _=1,limit or 20000 do
  for _,c in ipairs(commits)do
   if c.ticket and c.ticket.state=='pending' then
    local w=ctx.byCommit[c]
    if not w then w={index=#ctx.windows+1,commit=c,offset=-1};ctx.byCommit[c]=w;ctx.windows[#ctx.windows+1]=w end
    w.offset=w.offset+1
    for _,inj in ipairs(inject or {})do
     if not inj.done and inj.window==w.index and inj.offset==w.offset then
      inj.done=true;ctx.fired=ctx.fired+1
      inj.pendingAtWrite=c.ticket.state=='pending'
      inj.frame=frame
      inj.fn(ctx,w)
      inj.pendingAfterWrite=c.ticket.state=='pending'
     end
    end
   end
  end
  for _,w in ipairs(ctx.windows)do
   if not w.ended and w.commit.ticket.state~='pending' then
    w.ended,w.state,w.reason=frame,w.commit.ticket.state,w.commit.ticket.reason
   end
  end
  if perFrame then perFrame(ctx) end
  local busy=Nexus.Scheduler.Pending('data-retention.enforce')
  for _,c in ipairs(commits)do if c.ticket and c.ticket.state=='pending' then busy=true end end
  if busy then quiet=0 else quiet=quiet+1 end
  if quiet>20 then ctx.rested=true break end
  Step(1)
 end
 check(ctx.rested,'the ranked run and its retries came to rest')
 for _,inj in ipairs(inject or {})do
  check(inj.done and inj.pendingAtWrite,'injection reached retention window '..inj.window..' at offset '..inj.offset..' while the commit was pending')
 end
 for _,w in ipairs(ctx.windows)do
  check(w.commit.ticket.state~='pending','retention window '..w.index..' ended ('..tostring(w.commit.ticket.state)..')')
 end
 return ctx
end

local function Receive(name,values)
 local p=Player(name)
 local before={p.dps.lk,p.ts.lk,p.duration.lk}
 local ok=fx:Receive(name,'lk',values)
 if ok~=true then p.dps.lk,p.ts.lk,p.duration.lk=before[1],before[2],before[3] end
 return ok==true
end

-- The durable rows equal `kept` (name -> dps) exactly, with identity, fields,
-- public reads and exact ordinary and locked evidence.
local function Expect(tag,kept)
 local want={}
 for name,dps in pairs(kept)do want[Own(name)]=dps end
 local extra,missing={},{}
 for owner,row in pairs(Lk())do if not want[owner] then extra[owner]=row.dps end end
 for owner,dps in pairs(want)do local row=Lk()[owner];if not(row and row.dps==dps) then missing[owner]=tostring(row and row.dps)..'/'..dps end end
 check(next(extra)==nil and next(missing)==nil,tag..': Lich King rows are exactly the expected set; unexpected: '..Names(extra)..'; missing or wrong: '..Names(missing))
 for name,dps in pairs(kept)do
  local p,row=Player(name),Lk()[Own(name)]
  check(row.ownerKey==p.owner and row.ownerVerified==true and row.player==p.name and row.class==p.class
   and row.fingerprint==p.fingerprint and row.ts==p.ts.lk and row.buildId==(p.build=='present' and p.buildId or row.buildId),
   tag..': '..name..' keeps identity and record fields')
  local public=Nexus.DpsCapture.GetCharacterBest('lk',p.name,p.owner)
  check(public and public.dps==dps and List(public.echoes)==List(p.dpsOrdinary) and List(public.lockedEchoes)==List(p.dpsLocked),
   tag..': '..name..' public read and exact ordinary/locked evidence (stored inline='..tostring(row.echoes~=nil)
   ..', resolved '..#List(public and public.echoes)..'/'..#List(p.dpsOrdinary)..' bytes)')
 end
 if Player('Alpha') then
  local dummy=(Dps().characterBest or {}).dummy or {}
  check(dummy[Own('Alpha')] and dummy[Own('Alpha')].dps==48000 and next(dummy,next(dummy))==nil,tag..': the Dummy category is unchanged')
 end
end

local function RetentionCommits()
 local n=0;for _,c in ipairs(commits)do if c.dps or c.guarded then n=n+1 end end;return n
end
local summary={}

-- The unchanged policy on the fixture rows: Alpha and fillers C-Z are the top
-- 25, Pat is kept by the PRIEST minimum; fillers A-B, Lowell, Lowry removed.
local BASE={Alpha=52000,Pat=10000}
for i=3,26 do BASE['Filler'..string.char(64+i)]=40000+i end

------------------------------------------------------------------------
-- 1. Control: no concurrent write. Normal ranked pruning works and persists.
------------------------------------------------------------------------
Boot()
local ctx=Drive()
check(#ctx.windows>=1 and commits[1].dps~=nil,'control: the ranked run committed a DPS trim through a pending commit')
Expect('control',BASE)
check((Nexus.DataRetention.Stats(NexusDB) or {}).characterBestRemoved==4,'control: the run reports 4 removed rows')
H=F.Reload();Expect('control after reload',BASE)
summary[#summary+1]='control:'..RetentionCommits()..'c'

------------------------------------------------------------------------
-- 2. Writes accepted while the ranked commit that removes rows is pending:
-- a new high record (Kilo 60000, known-zero locked) displaces fillers; an
-- improvement (Lowell 30001 -> 59000) changes it from removed to kept; a new
-- low record (November 31000) is legitimately removed by the fresh
-- evaluation; a worse record and a duplicate stay refused.
-- Fresh evaluation: Kilo, Lowell, Alpha and fillers E-Z are the top 25, Pat
-- by the class minimum; fillers A-D, November and Lowry are removed.
------------------------------------------------------------------------
local FRESH={Kilo=60000,Lowell=59000,Alpha=52000,Pat=10000}
for i=5,26 do FRESH['Filler'..string.char(64+i)]=40000+i end
Boot()
local statsBefore,refusal
local accepted={}
ctx=Drive({{window=1,offset=0,fn=function()
 statsBefore=Nexus.DataRetention.Stats(NexusDB)
 accepted.kilo=Receive('Kilo',{dps=60000,ts=L.STAMP+300})
 accepted.lowell=Receive('Lowell',{dps=59000,ts=L.STAMP+301})
 accepted.november=Receive('November',{dps=31000,ts=L.STAMP+302})
 accepted.worse=Receive('Alpha',{dps=50000,ts=L.STAMP+303})
 accepted.duplicate=Receive('Kilo',{dps=60000,ts=L.STAMP+300})
end}},function(c)
 local w=c.windows[1]
 if w and not refusal and w.commit.ticket.state~='pending' then
  refusal={state=w.commit.ticket.state,reason=w.commit.ticket.reason,stats=Nexus.DataRetention.Stats(NexusDB),
   kilo=Lk()[Own('Kilo')],lowell=Lk()[Own('Lowell')]}
 end
end)
check(accepted.kilo and accepted.lowell and accepted.november and not accepted.worse and not accepted.duplicate,
 'stale window: the new, improved and low records are accepted; the worse and duplicate records are refused')
check(commits[1].dps~=nil and commits[1].dps.characterBest.lk[Own('Lowell')]==nil,'stale window: the pending commit was prepared to remove rows (Lowell among them)')
Expect('fresh evaluation',FRESH)
check((Nexus.DataRetention.Stats(NexusDB) or {}).characterBestRemoved==6,'fresh evaluation: 6 rows removed (fillers A-D, November, Lowry)')
check(refusal and refusal.state=='failed' and refusal.reason=='PUBLICATION_SOURCE_CHANGED',
 'stale window: the older snapshot is refused at publication: '..tostring(refusal and refusal.state)..' '..tostring(refusal and refusal.reason))
check(refusal.kilo and refusal.kilo.dps==60000 and refusal.lowell and refusal.lowell.dps==59000,'stale window: the accepted records stay in the durable store after the refusal')
check(refusal.stats==nil or (statsBefore and refusal.stats.lastRun==statsBefore.lastRun),'stale window: the refused run reports no removal or completion')
check(#ctx.windows>=2,'stale window: the run is prepared again from the current rows ('..#ctx.windows..' windows)')
check(RetentionCommits()<=3,'stale window: bounded re-preparation ('..RetentionCommits()..' commits)')
summary[#summary+1]='stale:'..RetentionCommits()..'c'
-- The Leaderboard shows the retained records with their exact evidence.
L.Open(H,'lk')
local rows=L.RenderedRows(H)
local shown={}
for i,row in ipairs(rows)do shown[row.data.ownerKey]=i end
for _,name in ipairs({'Kilo','Lowell','Alpha','Pat'})do
 check(shown[Own(name)],'Leaderboard: '..name..' is a rendered row')
 local det=L.Select(H,shown[Own(name)])
 check(det.row and det.row.ownerKey==Own(name) and List(det.ordinary)==List(Player(name).dpsOrdinary),'Leaderboard: '..name..' detail shows the exact ordinary Echoes')
end
for _,name in ipairs({'November','Lowry','FillerA','FillerD'})do check(not shown[Own(name)],'Leaderboard: removed '..name..' is not shown') end
Nexus.Leaderboard.Hide()
H=F.Reload();Expect('fresh evaluation after reload',FRESH)
-- Supported evidence cleanup keeps every retained record resolvable.
local gc
for _=1,4000 do
 gc=Nexus.DataCompaction.CollectGarbage(NexusDB)
 local busy=gc and gc.blocked and (gc.reason=='ROOT_MUTATION_PENDING' or gc.reason=='ROOT_ADMISSION_PENDING')
 if not (gc and (gc.pending or busy)) then break end
 Step(1)
end
check(gc and not gc.pending and not gc.blocked,'evidence cleanup completes: '..tostring(gc and gc.reason))
Expect('fresh evaluation after evidence cleanup',FRESH)

------------------------------------------------------------------------
-- 3. Accepted writes in two separate windows: Kilo in the first pending
-- commit, Lowell's improvement in the commit prepared after the refusal.
------------------------------------------------------------------------
Boot()
local firstEnded
ctx=Drive({
 {window=1,offset=0,fn=function() check(Receive('Kilo',{dps=60000,ts=L.STAMP+300}),'separate windows: Kilo accepted') end},
 {window=2,offset=0,fn=function() check(Receive('Lowell',{dps=59000,ts=L.STAMP+301}),'separate windows: Lowell accepted') end},
},function(c)
 local w=c.windows[1]
 if w and w.ended and not firstEnded then
  firstEnded=true
  local row=Lk()[Own('Kilo')]
  check(row and row.dps==60000,'separate windows: Kilo is durable when the first window ends ('..tostring(row and row.dps)..')')
 end
end)
-- Kilo, Lowell, Alpha and fillers E-Z are the top 25; Pat by the minimum.
local SEP={Kilo=60000,Lowell=59000,Alpha=52000,Pat=10000}
for i=5,26 do SEP['Filler'..string.char(64+i)]=40000+i end
Expect('separate windows',SEP)
check(RetentionCommits()<=4,'separate windows: bounded re-preparation ('..RetentionCommits()..' commits)')
H=F.Reload();Expect('separate windows after reload',SEP)
summary[#summary+1]='separate:'..RetentionCommits()..'c'

------------------------------------------------------------------------
-- 4. Finite contention: a better Kilo record on every frame for 400 frames
-- (20 s) from the first pending commit. Every accepted value stays durable on
-- every frame; each refused commit is prepared again once, after the busy
-- chain's growing delay (5 s, 10 s, ...); after the burst the run settles.
------------------------------------------------------------------------
Boot()
local burst={left=nil,value=60000,last=nil}
ctx=Drive({{window=1,offset=0,fn=function() burst.left=400 end}},function()
 -- The previous frame's accepted value must still be durable before the next write.
 if burst.last then
  local row=Lk()[Own('Kilo')]
  check(row and row.dps==burst.last,'burst frame '..frame..': the last accepted Kilo record is durable ('..tostring(row and row.dps)..'/'..burst.last..')')
 end
 if burst.left and burst.left>0 then
  burst.value=burst.value+1
  if Receive('Kilo',{dps=burst.value,ts=L.STAMP+300+(burst.value-60000)}) then burst.last=burst.value end
  burst.left=burst.left-1
 end
end)
check(burst.left==0 and burst.last==60400,'burst: 400 better records were accepted')
-- Kilo, Alpha and fillers D-Z are the top 25; Pat by the minimum; Lowell
-- (30001) and Lowry are removed.
local BURST={Kilo=60400,Alpha=52000,Pat=10000}
for i=4,26 do BURST['Filler'..string.char(64+i)]=40000+i end
Expect('burst',BURST)
local refused,gaps=0,{}
for i,w in ipairs(ctx.windows)do
 if w.state=='failed' then
  refused=refused+1
  check(w.reason=='PUBLICATION_SOURCE_CHANGED','burst: window '..i..' was refused as stale: '..tostring(w.reason))
  local nextWindow=ctx.windows[i+1]
  check(nextWindow~=nil,'burst: refused window '..i..' is prepared again')
  local gap,want=nextWindow.commit.frame-w.ended,100*2^(refused-1)
  gaps[#gaps+1]=gap
  check(gap>=want and gap<=want+100,'burst: preparation '..(refused+1)..' follows the chain delay ('..gap..' frames, delay '..want..')')
 end
end
check(refused>=2 and ctx.windows[#ctx.windows].state=='committed','burst: '..refused..' refusals, then a committed run')
check(RetentionCommits()==refused+1,'burst: exactly one new preparation per refusal ('..RetentionCommits()..' commits)')
summary[#summary+1]='burst:'..RetentionCommits()..'c/gaps '..table.concat(gaps,',')

------------------------------------------------------------------------
-- 5. A write during the ranked run's overlay scan (the one yield before its
-- DPS copy) is part of the copy: no refusal, one commit. Four unrelated
-- remote pages (no records, within the page budgets) make the catalog larger
-- than one bounded read, so the scan yields.
------------------------------------------------------------------------
Boot({extraBuilds=4})
-- The start-up run leaves its scan job open (known, see
-- retention_ranked_marker_pass), so the first request ends as a marker pass;
-- the next request scans afresh.
Drive()
local markerPass=false
for _,r in ipairs(results)do if type(r.result)=='table' and r.result.overlayScanIncomplete~=nil then markerPass=true end end
check(markerPass,'fixture: the first request ended as a marker pass')
local base,scanWrite=#commits,nil
ctx=Drive(nil,function()
 local last=results[#results]
 if not scanWrite and last and type(last.result)=='table' and last.result.pending==true
  and last.result.workDomain=='retention-overlay-scan' then
  scanWrite={commitsBefore=#commits,ok=Receive('Kilo',{dps=60000,ts=L.STAMP+300})}
 end
end)
check(scanWrite and scanWrite.ok and scanWrite.commitsBefore==base,'scan yield: Kilo was accepted while the ranked run scanned, before its copy')
local copied=commits[base+1] and commits[base+1].dps and commits[base+1].dps.characterBest.lk[Own('Kilo')]
check(copied and copied.dps==60000,'scan yield: the ranked copy includes the write')
check(#ctx.windows==1 and ctx.windows[1].state=='committed','scan yield: no refusal, one commit')
-- Kilo, Alpha and fillers D-Z are the top 25; Pat by the minimum.
local KSET={Kilo=60000,Alpha=52000,Pat=10000}
for i=4,26 do KSET['Filler'..string.char(64+i)]=40000+i end
Expect('scan yield',KSET)

------------------------------------------------------------------------
-- 6. A writer that calls the catalog before it stores its row: Quinn has no
-- build page, so the record asks the catalog for one (refused while the
-- ranked commit is in flight; that missing page is F5, not this defect). A
-- rebind request is pending from the start of the window, so the catalog
-- call could pump the in-flight commit to publication inside the write
-- (#86). The window's first and last two offsets are exercised; the last is
-- where one slice is left.
------------------------------------------------------------------------
local function RebindAtStart() return {window=1,offset=0,fn=function()
 Nexus.BuildCatalog.RequestAuthorityRebindV1('SOURCE_REBIND_REQUIRED') end} end
Boot()
ctx=Drive({RebindAtStart()})
local W=ctx.windows[1].offset+1
check(W>=3,'nested writer: the pending window lasts '..W..' frames with the rebind request')
summary[#summary+1]='nested:W='..W
-- Quinn, Alpha and fillers D-Z are the top 25; Pat by the minimum.
local QSET={Quinn=58000,Alpha=52000,Pat=10000}
for i=4,26 do QSET['Filler'..string.char(64+i)]=40000+i end
for _,k in ipairs({0,W-2,W-1})do
 Boot()
 local info
 ctx=Drive({RebindAtStart(),{window=1,offset=k,fn=function()
  local bundle=NexusDB.authorityBundle
  info={requested=Nexus.BuildCatalog.RebindRequired(),ok=Receive('Quinn',{dps=58000,ts=L.STAMP+320})}
  info.inside=NexusDB.authorityBundle~=bundle
 end}})
 check(info and info.requested and info.ok,'nested writer +'..k..': Quinn is accepted with a rebind request pending')
 check(not info.inside,'nested writer +'..k..': no catalog publication happened inside the write')
 check(ctx.windows[1].offset+1==W,'nested writer +'..k..': the write pumped no catalog slice (window '..(ctx.windows[1].offset+1)..' frames, discovered '..W..')')
 Expect('nested writer +'..k,QSET)
 local row,pages=Lk()[Own('Quinn')],0
 for _,b in pairs(Bundle().communityBuilds or {})do if b.ownerKey==Own('Quinn') then pages=pages+1 end end
 check(pages<=1 and (pages==0)==(row.buildId==nil),'nested writer +'..k..': page and link agree ('..pages..' page, F5 when none)')
end

------------------------------------------------------------------------
-- 7. Immediate refusal: with no build pages the ranked commit publishes
-- inside CommitMaintenance. A metadata enrichment (the same FillerZ record
-- with its locked Echoes) is accepted between the ranked copy and that call
-- (injected just before the call; no product writer runs there today), so
-- the synchronous publication is refused and the run is prepared again.
------------------------------------------------------------------------
Boot({fillersOnly=true})
local enrich
beforeCommit=function(rec)
 if rec.dps then
  local p=Player('FillerZ')
  p.locked=L.LockedRows(100,2);p.dpsLocked=L.DpsRows(p.locked)
  enrich={open=Nexus.LoadoutEvidence.CandidateOpen(),ok=Receive('FillerZ',{dps=p.dps.lk,ts=p.ts.lk})}
 end
end
ctx=Drive()
beforeCommit=nil
check(enrich and enrich.ok and enrich.open,'immediate: the enrichment is accepted with the ranked transaction open')
local IMM={}
for i=2,26 do IMM['Filler'..string.char(64+i)]=40000+i end
Expect('immediate',IMM)
check(commits[1].dps and commits[1].first==false and commits[1].why=='PUBLICATION_SOURCE_CHANGED',
 'immediate: the ranked commit is refused inside CommitMaintenance: '..tostring(commits[1].first)..' '..tostring(commits[1].why))
check(RetentionCommits()==2 and commits[#commits].first==true,'immediate: prepared again once and published')

------------------------------------------------------------------------
-- 8. Unchanged path: a ranked run that removes nothing (25 Lich King rows)
-- carries no DPS copy and no guard; a record accepted in its window is kept
-- and the commit is not refused. The new row waits for the next run.
------------------------------------------------------------------------
Boot({fillers=21})
ctx=Drive({{window=1,offset=0,fn=function() check(Receive('Kilo',{dps=60000,ts=L.STAMP+300}),'no removals: Kilo accepted') end}})
check(#ctx.windows==1 and ctx.windows[1].state=='committed' and not commits[1].guarded and not commits[1].dps,
 'no removals: one unguarded commit without a DPS copy')
local NOREM={Kilo=60000,Alpha=52000,Lowell=30001,Lowry=30002,Pat=10000}
for i=1,21 do NOREM['Filler'..string.char(64+i)]=40000+i end
Expect('no removals',NOREM)

------------------------------------------------------------------------
-- 9. An overlay eviction decided from the copy: Oscar (HUNTER) has an
-- automatic page and no record, so the run evicts the page as an orphan and
-- removes no DPS row. Oscar's record, referencing that page, is accepted in
-- the window: the eviction is refused and the page is kept.
------------------------------------------------------------------------
Boot({fillers=21,orphan=true})
ctx=Drive({{window=1,offset=0,fn=function() check(Receive('Oscar',{dps=45000,ts=L.STAMP+330}),'orphan page: Oscar accepted') end}})
check(Nexus.BuildCatalog.Get(Player('Oscar').buildId)~=nil,'orphan page: the page the accepted record references is kept')
check(commits[1].guarded and not commits[1].dps,'orphan page: the pending commit evicts a page (guarded) and removes no DPS row')
check(ctx.windows[1].state=='failed' and ctx.windows[1].reason=='PUBLICATION_SOURCE_CHANGED','orphan page: the eviction from the older copy is refused')
-- 26 rows: the top 25 are all but Pat, who is kept by the PRIEST minimum.
local ORPH={Oscar=45000,Alpha=52000,Lowell=30001,Lowry=30002,Pat=10000}
for i=1,21 do ORPH['Filler'..string.char(64+i)]=40000+i end
Expect('orphan page',ORPH)

------------------------------------------------------------------------
-- 10. Persisted first observations of retention markers are not refreshed
-- by a refused run and its retry. A first run records them; a later run
-- (after November's record) is refused because Kilo's record arrives in its
-- window, then prepared again.
------------------------------------------------------------------------
Boot({markers=2})
Drive()
local seen={}
for k,v in pairs((rawget(Bundle(),'dataRetention') or {}).markerFirstSeen or {})do seen[k]=v end
check(next(seen)~=nil,'markers: the first run recorded first observations')
check(Receive('November',{dps=31000,ts=L.STAMP+302}),'markers: November accepted before the next run')
ctx=Drive({{window=1,offset=0,fn=function() check(Receive('Kilo',{dps=60000,ts=L.STAMP+300}),'markers: Kilo accepted in the window') end}})
-- Kilo, Alpha and fillers D-Z are the top 25; Pat by the minimum; filler C
-- and November are removed.
local MSET={Kilo=60000,Alpha=52000,Pat=10000}
for i=4,26 do MSET['Filler'..string.char(64+i)]=40000+i end
Expect('markers',MSET)
local after=(rawget(Bundle(),'dataRetention') or {}).markerFirstSeen or {}
local same=true
for k,v in pairs(seen)do if after[k]~=v then same=false end end
for k in pairs(after)do if seen[k]==nil then same=false end end
check(same,'markers: the persisted first observations are unchanged')
check(ctx.windows[1].state=='failed' and ctx.windows[#ctx.windows].state=='committed','markers: refused once, then committed')

------------------------------------------------------------------------
-- 11. The saved database is replaced after a refusal: the retry resolves the
-- bound database, ranks its rows and keeps the accepted record; the replaced
-- database kept the record too (its refused commit wrote nothing).
------------------------------------------------------------------------
Boot()
local old
ctx=Drive({{window=1,offset=0,fn=function() check(Receive('Kilo',{dps=60000,ts=L.STAMP+300}),'replacement: Kilo accepted') end}},function(c)
 local w=c.windows[1]
 if w and w.state=='failed' and not old then
  old=NexusDB
  NexusDB=assert(loadstring('return '..F.Serialize(NexusDB)))()
  Nexus.BuildCatalog.Status()
 end
end)
Expect('replacement',KSET)
check(old and ctx.windows[1].reason=='PUBLICATION_SOURCE_CHANGED','replacement: the database was replaced after the refusal')
check(Nexus.BuildCatalog.BoundDatabase()==NexusDB,'replacement: the catalog binds the new database')
local oldRow=old.authorityBundle.dpsCapture.characterBest.lk[Own('Kilo')]
check(oldRow and oldRow.dps==60000,'replacement: the replaced database kept the accepted record')

print('PASS retention_ranked_dps_preservation: control; writes in a pending ranked commit (new, improved, low, worse, duplicate) kept and re-ranked; separate windows; contention with chain delays; scan-yield write; nested catalog writer under a pending rebind; immediate refusal; unguarded no-removal run; orphan-page eviction refused; marker first observations kept; database replaced after a refusal ['..table.concat(summary,' ')..'] checks='..checks)
