-- Locked-shape capture, part 3 of 4 (tests-first): the support report shows the
-- cached capture as one bounded, private block, and collecting it reads nothing.
-- At 5a8299c the prepared report has no such block and the adapter has no
-- LockedShapeView (source reading).
-- Contract: TEST_CONTRACT.md of the locked-shape tests-first phase, sections 1, 3 and 5-7.
-- The block is taken from the real prepared report: SupportReport.Prepare, and
-- the full /nexus report page route (Prepare report file, which stores the
-- report in the isolated NexusSupport component, loaded on demand the way the
-- client loads it). Collection reads Nexus.GameAdapter.LockedShapeView, looked
-- up when the report is collected; the test replaces it with missing, failing,
-- corrupt and distinctive stand-ins. Inside each collection window the test
-- counts every PerkService and OrbService member, the listed adapter, Orb
-- adapter, Orb runtime and Store write entries, GetSpellInfo, LoadAddOn and the
-- error and incident recorders, and compares counters, revisions, dirty flags,
-- saved data, the recovery view, the run history and the samples.
-- Real TOC boot, adapter, Orb runtime, report builder and page; the fake
-- services of orbs_support.lua; artificial IDs and names (markers ZQ_). No Orb
-- run is started and nothing is spent, selected or locked. Every check is
-- evaluated; the test prints a summary and fails at the end if any check failed.
local H,T=dofile('tests/prototype/locked_shape_support.lua')
local A,M,O=H.A,H.M,H.O
local expect,guard,printable=T.expect,T.guard,T.printable

H.now=math.floor(H.now)+100
local BASE_GRANTED=H.Clone(H.granted)
local function trusted()
 H.holdGrantedResponse=nil;O.known=true;H.playerLevel=40
 H.granted=H.Clone(BASE_GRANTED);A.Owned()
 H.locked={};A.LockedOwned()
end
local function E(id,fields)
 local e={spellId=id}
 for k,v in pairs(fields or {}) do e[k]=v end
 return e
end
local function sixPlus()
 return {E(410001,{quality=1}),E(410002,{quality=2}),E(410003,{quality=0}),E(410004,{quality=3}),
  E(410005,{quality=0}),E(410006,{quality=3}),E(410001,{quality=1})}
end
local function facts(t,keys)
 if type(t)~='table' then return printable(t) end
 local out={}
 for _,k in ipairs(keys) do out[#out+1]=k..'='..printable(t[k]) end
 return table.concat(out,' ')
end

-- The companion storage, loaded on demand as the client loads it.
LoadAddOn=function(name)
 if name~='NexusSupport' then return false end
 dofile('companion/NexusSupport/Storage.lua');H.Fire('ADDON_LOADED','NexusSupport');return true
end

-- Spies: counted only inside a collection window; behaviour is unchanged.
local SPY={on=false,calls={}}
local function wrap(owner,name,label)
 if type(owner)~='table' or type(owner[name])~='function' then return end
 local fn=owner[name]
 owner[name]=function(...)
  if SPY.on then SPY.calls[label]=(SPY.calls[label] or 0)+1 end
  return fn(...)
 end
end
local function wrapAll(owner,prefix)
 if type(owner)~='table' then return end
 local names={}
 for k,v in pairs(owner) do if type(v)=='function' then names[#names+1]=k end end
 for _,k in ipairs(names) do wrap(owner,k,prefix..k) end
end
wrapAll(ProjectEbonhold.PerkService,'PerkService.')
wrapAll(ProjectEbonhold.OrbService,'OrbService.')
wrap(ProjectEbonhold.PlayerRunService,'GetCurrentData','PlayerRunService.GetCurrentData')
wrap(ProjectEbonholdOptionsService,'GetSetting','Options.GetSetting')
wrap(ProjectEbonholdOptionsService,'SetSetting','Options.SetSetting')
for _,k in ipairs({'Owned','LockedOwned','Catalog','CheckCatalogSource','AssignedWishlist','Wishlist','Slots',
 'EchoActiveSlotGeneration','AutomationSignature','Board','Charges','GrantedCount','DisabledLevers','DiscoverySynced',
 'GetWishlistCandidates','GetLoadoutCandidates','GetFirstRunWishlist','ConsumeDirty','Poll','RequestGranted',
 'RunBoundaryReset','RequestSlots','LockPerk','UnlockPerk','Take','Banish','Reroll','Freeze','Activate','Save',
 'UploadWishlist','ToggleLever','SetSoloPicker','RestoreAutoAccept','ConsumeUserAction','ExternalActionSeen',
 'DumpLockedPerksRaw','OrdinaryBoardAllowed','InFlight','PendingActions','UnconfirmedLatch',
 'Init','MaxPermanentEchoes','UnlockedSlots'}) do
 wrap(A,k,'GameAdapter.'..k)
end
for _,k in ipairs({'Read','Balance','ServiceState','RequestRefresh','CaptureStart','TransportStart','Watch',
 'Unwatch','Acquire','Rebind','Spend','Select','Release'}) do
 wrap(A.Orbs,k,'Orbs.'..k)
end
for _,k in ipairs({'Status','Recheck','Pump','Start','Prepare','Confirm','Resume','Pause','Stop','SetLimit',
 'SetRecycle','SetSource','Exclude','ClearExclusions','SuggestSources','UseAssignedWishlist','TrackBalance',
 'NewRunDraft','EditLimitText','CancelLimitEdit','LimitDraft','PrepareLimitIncrease','ConfirmLimit',
 'ContinueBegin','ContinueCancel','ContinueConfirm','BlocksOrdinary','BlockReason','CompactStatus',
 'SelectWishlist','MoveTarget'}) do
 wrap(M,k,'OrbRuntime.'..k)
end
wrap(Nexus.MainInternals and Nexus.MainInternals.StoreAuthorityOwner,'UpdateStateV1','Store.UpdateStateV1')
wrap(Nexus.Errors,'Record','Errors.Record')
wrap(Nexus.SupportIncidents,'Record','SupportIncidents.Record')
wrap(_G,'GetSpellInfo','GetSpellInfo')
wrap(_G,'LoadAddOn','LoadAddOn')
local function window(fn)
 SPY.calls={};SPY.on=true
 local ok,err=T.realPcall(fn)
 SPY.on=false
 return ok,err,SPY.calls
end

-- P0. Before any refused read: "not observed" (a pristine instance, and the live
-- adapter whose reads so far were all accepted), apart from "unavailable" (no
-- accessor). Collection with the pristine accessor reads nothing.
T.scenario('P0 not observed, and unavailable',function()
 trusted()
 local pristine,perr=T.pristineAdapter()
 guard(type(pristine)=='table','P0: fixture: a pristine adapter instance loads in its own sandbox',perr)
 pristine=type(pristine)=='table' and pristine or {}
 local pv,pwhy=T.call(pristine.LockedShapeView)
 expect(pv~=nil,'P0: the pristine instance has LockedShapeView() and it answers',pwhy)
 T.checkShape('P0 pristine',pv)
 expect(pv~=nil and pv.observed==false,'P0: before any normal read nothing is captured',pv and pv.observed)
 local lv=T.shape()
 expect(lv~=nil and lv.observed==false,'P0: the live adapter has captured nothing: every locked read so far was accepted',
  lv and lv.observed)
 local real=A.LockedShapeView
 local text
 local ok,err,calls=window(function()
  A.LockedShapeView=pristine.LockedShapeView
  local okP,p=T.realPcall(T.prepared)
  A.LockedShapeView=real
  if not okP then error(p,0) end
  text=p
 end)
 A.LockedShapeView=real
 guard(ok,'P0: the report is prepared',err)
 guard(next(calls)==nil,'P0: collection called no getter, read, request, status, spend, lock, recorder or writer',T.callList(calls))
 local t,all=T.checkBlock('P0 pristine',text or '',{'ZQ_'})
 expect(#all>0 and t.observed=='no','P0: the block says observed=no',t.observed)
 local invented={}
 for _,k in ipairs(T.BLOCK_CAPTURE_KEYS) do
  if t[k]~=nil and not T.UNSEEN[t[k]] then invented[#invented+1]=k..'='..t[k] end
 end
 expect(#all>0 and #invented==0,'P0: and invents no capture fact',table.concat(invented,','))
 A.LockedShapeView=nil
 local okM,textM=T.realPcall(T.prepared)
 A.LockedShapeView=real
 guard(okM,'P0 missing: the report is still prepared without the accessor',textM)
 local tm,allm=T.checkBlock('P0 missing',okM and textM or '',{'ZQ_'})
 expect(#allm>0 and (tm.observed=='unavailable' or tm.observed=='unknown'),
  'P0 missing: without the accessor the block says unavailable, never no',tm.observed)
end)

-- P1. A refused normal read, then the full page route before any Orb run:
-- /nexus report and Prepare report file. The stored report carries the block,
-- equal to the accessor; the route reads nothing and changes nothing but the
-- support component's stored report.
T.scenario('P1 the full report file route before any Orb run',function()
 trusted()
 H.now=H.now+10
 local l,_,err=T.read(sixPlus())
 guard(l~=nil and l.synced==false,'P1: fixture: a normal locked read is refused',err or (l and l.synced))
 H.now=H.now+4
 -- The existing report readers first (RunLog initializes the runtime once),
 -- then the counters, so that nothing outside the window can move them.
 local rv0,log0=T.serialize(M.RecoveryView()),T.serialize(M.RunLog('current'))
 local v0,t0,r0=T.shape(),T.trust(),T.readiness()
 A.ConsumeDirty()
 local c0,db0=T.counters(),T.serialize(NexusDB)
 local req0=T.serialize({H.grantedRequests or 0,H.slotRequests or 0,O.requests or 0,#H.actions})
 local meta,why
 local ok,errW,calls=window(function()
  SlashCmdList.NEXUS('report')
  meta,why=Nexus.SupportReportUI.PrepareFile(false)
 end)
 guard(ok,'P1: /nexus report and Prepare report file completed',errW)
 local other={}
 for k,n in pairs(calls) do if k~='LoadAddOn' then other[#other+1]=k..' x'..n end end
 table.sort(other)
 guard(#other==0,'P1: the page and the file route called no getter, read, request, catalog, status, spend, lock, recorder or writer',
  table.concat(other,', '))
 guard((calls.LoadAddOn or 0)<=1,'P1: the only load is the support component, on demand',calls.LoadAddOn)
 T.sameCounters('P1',c0,T.counters())
 guard(T.serialize(NexusDB)==db0,'P1: saved data is unchanged')
 local req1=T.serialize({H.grantedRequests or 0,H.slotRequests or 0,O.requests or 0,#H.actions})
 guard(req1==req0,'P1: no service request or action was sent',req0..' -> '..req1)
 local dirtyBoard,dirtySlots,dirtyData=A.ConsumeDirty()
 guard(not dirtyBoard and not dirtySlots and not dirtyData,'P1: collection marked nothing dirty',
  printable(dirtyBoard)..'/'..printable(dirtySlots)..'/'..printable(dirtyData))
 guard(T.serialize(T.trust())==T.serialize(t0) and T.serialize(T.readiness())==T.serialize(r0),
  'P1: the ownership samples and the Orb observation are neither changed nor refreshed')
 expect(type(v0)=='table' and v0.observed==true and T.serialize(T.shape())==T.serialize(v0),
  'P1: the capture is neither changed nor refreshed')
 local stored=type(NexusSupportDB)=='table' and type(NexusSupportDB.report)=='table'
  and type(NexusSupportDB.report.chunks)=='table'
 guard(meta~=nil and stored,'P1: Prepare report file stored the report in the support component',why)
 local text=stored and table.concat(NexusSupportDB.report.chunks,'') or ''
 guard(text:find('Orb action: none unresolved',1,true)~=nil and text:find('no run in this session',1,true)~=nil,
  'P1: the stored report keeps the existing Orb lines')
 guard(#T.lines(text,'Orb readiness')>0 and #T.lines(text,'Ownership sample')>0,
  'P1: and the Orb readiness and ownership sample blocks')
 local t=T.checkBlock('P1 stored report',text,{'ZQ_'})
 T.matchView('P1 stored report',t,v0)
 local _,d2=T.read(sixPlus())
 guard(d2.calls==1 and d2.serial==(c0.lockedCalls or 0)+1,
  'P1: liveness: the next normal locked read takes the next serial, so collection read nothing',
  printable(c0.lockedCalls)..' -> '..printable(d2.serial))
 guard(T.serialize(M.RecoveryView())==rv0 and T.serialize(M.RunLog('current'))==log0,
  'P1: the recovery view and the run history are unchanged')
 guard(H.Count('orb-spend')==0 and H.Count('take')==0,'P1: no Orb was spent and no Echo selected')
end)

-- P2. Prepare and the pure accessors write nothing, not even the support
-- component; the copied summary does not carry the block.
T.scenario('P2 Prepare and the accessors write nothing',function()
 local s0=T.serialize(NexusSupportDB)
 local text,summary
 local ok,err,calls=window(function()
  T.shape();T.trust();T.readiness()
  text=T.prepared()
  summary=Nexus.SupportReport.Summary()
  Nexus.SupportReport.OrbLines()
 end)
 guard(ok,'P2: the collection window completed',err)
 guard(next(calls)==nil,'P2: the accessors, Prepare, the summary and the Orb lines called nothing, loaded nothing and recorded nothing',
  T.callList(calls))
 guard(T.serialize(NexusSupportDB)==s0,'P2: the stored support report is unchanged: only the explicit file route writes it')
 guard(type(summary)=='string' and #T.lines(summary,'Locked shape')==0,'P2: the copied summary does not carry the block')
 local t=T.checkBlock('P2',text or '',{'ZQ_'})
 expect(t.observed=='yes' and t.status=='captured','P2: the prepared report shows the capture',facts(t,{'observed','status'}))
end)

-- P3. The accessor returns copies.
T.scenario('P3 the accessor returns copies',function()
 local v=T.shape()
 local rec=T.record(v)
 T.realPcall(function()
  v.serial=-1;v.status='ZQ_MUTATED';v.observed=false;v.rows=0
  v.row[1].p=99;v.row[1].k='ZQ_MUTATED';v.row[2]=nil
 end)
 local w=T.shape()
 expect(type(v)=='table' and type(w)=='table' and not rawequal(v,w) and T.record(w)==rec and w.observed==true,
  'P3: each call returns a new table; changing it changes nothing recorded',facts(w,{'observed','serial','status','rows'}))
 expect(type(v)=='table' and type(w)=='table' and type(w.row)=='table' and not rawequal(w.row,v.row)
  and type(w.row[1])=='table' and w.row[1].p==0,'P3: the row list and its rows are new tables too')
end)

-- P4. Missing, failing or corrupt accessors and owners: the report is still
-- prepared, the other blocks stay, and nothing is guessed or leaked.
T.scenario('P4 missing, failing or corrupt accessors and owners',function()
 trusted()
 H.now=H.now+3
 T.read(sixPlus())
 local real=A.LockedShapeView
 local function raise() error('ZQ_SHAPE_THROW_MARKER Disposable A 410001',0) end
 local evil=setmetatable({},{__index=function() error('ZQ_SHAPE_INDEX_MARKER 410001',0) end})
 local corrupt={observed=true,serial=0/0,at=evil,age=-7,current='yes',laterReads=1e300,sampledGeneration=2.5,
  currentGeneration=-3,first='ZQ_FIRST_MARKER Disposable A 410001',copies=1/0,ids={},status='ZQ_STATUS_MARKER',rows=999,
  row='ZQ_ROWS_MARKER 410001'}
 for i=1,100 do corrupt['ZQjunk'..i]='ZQ_JUNK_MARKER Disposable A 410001' end
 local badRows={observed=true,serial=7,at=H.now,age=0,current=true,laterReads=0,sampledGeneration=0,currentGeneration=0,
  first='scalar_leaf',copies=2,ids=1,status='captured',rows=3,
  row={'ZQ_ROW_STRING_MARKER 410001',{p='ZQ_P',k='ZQ_K Disposable A',c=-1,n=0/0,im=99999,cm=64,e=-1},
   setmetatable({},{__index=function() error('ZQ_ROW_INDEX_MARKER 410001',0) end})}}
 local variants={
  {'missing',nil,'unavailable'},
  {'throws',raise,'unavailable'},
  {'not a table',function() return 'ZQ_SHAPE_STRING_MARKER Disposable A 410001' end,'unavailable'},
  {'raising index',function() return evil end,'unavailable'},
  {'observed not a boolean',function() return {observed='true',serial=5,status='captured'} end,'unavailable'},
  {'corrupt header',function() return corrupt end,'header'},
  {'corrupt rows',function() return badRows end,'rows'},
 }
 for _,c in ipairs(variants) do
  local tag='P4 '..c[1]
  A.LockedShapeView=c[2]
  local ok,text=T.realPcall(T.prepared)
  A.LockedShapeView=real
  guard(ok,tag..': the report is still prepared',text)
  text=ok and text or ''
  guard(text:find('Orb action: none unresolved',1,true)~=nil and text:find('no run in this session',1,true)~=nil,
   tag..': the existing Orb lines are kept')
  local o=T.tokens(T.lines(text,'Ownership sample'))
  guard(#T.lines(text,'Orb readiness')>0 and o['locked.observed']=='yes' and o['locked.rejection']=='over_cap',
   tag..': the Orb readiness and ownership sample blocks are kept unchanged',facts(o,{'locked.observed','locked.rejection'}))
  local t,all=T.checkBlock(tag,text,{'ZQ_'})
  if c[3]=='unavailable' then
   local shown={}
   for k,x in pairs(t) do if k~='observed' and not T.UNSEEN[x] then shown[#shown+1]=k..'='..x end end
   table.sort(shown)
   expect(#all>0 and (t.observed=='unavailable' or t.observed=='unknown') and #shown==0,
    tag..': the block says unavailable and shows no fact',printable(t.observed)..' '..table.concat(shown,','))
  elseif c[3]=='header' then
   local guessed={}
   for k,x in pairs(t) do
    local unknownRow=k:match('^r%d+$')~=nil and x:match('^%?%.%?%.%?%.%?%.%?%.%?%.%?$')~=nil
    if k~='observed' and not T.NULL[x] and not unknownRow then guessed[#guessed+1]=k..'='..x end
   end
   table.sort(guessed)
   expect(#all>0 and t.observed=='yes' and #guessed==0,tag..': observed=yes from the boolean, every other fact unknown',
    printable(t.observed)..' '..table.concat(guessed,','))
  else
   local okRows=true
   for i=1,3 do
    local x=t['r'..i]
    okRows=okRows and x~=nil and (x=='unknown' or x:match('^%?%.%?%.%?%.%?%.%?%.%?%.%?$')~=nil)
   end
   expect(t.serial=='7' and t.rows=='3' and t.first=='scalar_leaf' and okRows and t.r4==nil,
    tag..': the valid header is shown and each unreadable row is unknown, never guessed',
    facts(t,{'serial','rows','first','r1','r2','r3','r4'}))
  end
 end
 local realOwner=Nexus.GameAdapter
 for _,c in ipairs({{'owner missing',nil},
  {'owner raising',setmetatable({},{__index=function() error('ZQ_OWNER_MARKER 410001',0) end})}}) do
  local tag='P4 '..c[1]
  Nexus.GameAdapter=c[2]
  local ok,text=T.realPcall(T.prepared)
  Nexus.GameAdapter=realOwner
  guard(ok,tag..': the report is still prepared',text)
  local t,all=T.checkBlock(tag,ok and text or '',{'ZQ_'})
  expect(#all>0 and (t.observed=='unavailable' or t.observed=='unknown'),tag..': the block says unavailable',t.observed)
 end
 guard(Nexus.GameAdapter==realOwner and A.LockedShapeView==real,'P4: fixture: the owner and the accessor are restored')
end)

-- P5. The block shows what the accessor holds when the report is collected,
-- and the widest valid capture stays within 4096 bytes without losing a row
-- silently.
T.scenario('P5 the block shows the accessor, within its bounds',function()
 local real=A.LockedShapeView
 local standIn={observed=true,serial=4321,at=H.now-12,age=12,current=false,laterReads=3,sampledGeneration=2,
  currentGeneration=5,first='scalar_leaf',copies=2,ids=1,status='captured',rows=3,
  row={{p=0,k='-',c=0,n=0,im=0,cm=0,e=0},{p=1,k='i',c=1,n=2,im=1,cm=2,e=0},{p=1,k='i',c=0,n=0,im=0,cm=0,e=32}}}
 A.LockedShapeView=function() return H.Clone(standIn) end
 local ok,text=T.realPcall(T.prepared)
 A.LockedShapeView=real
 guard(ok,'P5 stand-in: the report is prepared',text)
 local t=T.checkBlock('P5 stand-in',ok and text or '',{})
 T.matchView('P5 stand-in',t,standIn)
 local wide={observed=true,serial=9999999,at=H.now,age=9999999,current=false,laterReads=9999999,sampledGeneration=9999999,
  currentGeneration=9999999,first='conflicting_alias',copies=9999999,ids=9999999,status='truncated',rows=64,row={}}
 for i=1,64 do
  wide.row[i]={p=i-1,k=i==1 and '-' or 'o',c=i==1 and 0 or 'x',n=9999999,im=2047,cm=31,e=63}
 end
 A.LockedShapeView=function() return H.Clone(wide) end
 local okW,textW=T.realPcall(T.prepared)
 A.LockedShapeView=real
 guard(okW,'P5 widest: the report is prepared',textW)
 local tw,allw=T.checkBlock('P5 widest',okW and textW or '',{})
 local shown=0
 for i=1,64 do if tw['r'..i]~=nil then shown=shown+1 end end
 local omitted=tw.omitted and tonumber(tw.omitted) or 0
 expect(#allw>0 and shown>=1 and shown+omitted==64 and tw.r65==nil,
  'P5 widest: 64 rows within 4096 bytes: every row is shown or declared omitted',shown..' shown, omitted '..printable(tw.omitted))
 expect(tw.status=='truncated' and tw.rows=='64' and tw.serial=='9999999','P5 widest: with its truncated status, row count and serial',
  facts(tw,{'status','rows','serial'}))
end)

-- P6. Each passive block stands alone.
T.scenario('P6 each passive block stands alone',function()
 trusted()
 H.now=H.now+3
 T.read(sixPlus())
 local realTrust,realView,realShape=A.OwnershipTrustView,M.ReadinessView,A.LockedShapeView
 A.OwnershipTrustView=function() error('ZQ_TRUST_THROW_MARKER',0) end
 M.ReadinessView=function() error('ZQ_VIEW_THROW_MARKER',0) end
 local ok,text=T.realPcall(T.prepared)
 A.OwnershipTrustView,M.ReadinessView=realTrust,realView
 guard(ok,'P6: the report is prepared while the ownership and readiness accessors fail',text)
 local t=T.checkBlock('P6 others failing',ok and text or '',{'ZQ_'})
 expect(t.observed=='yes' and t.status=='captured' and t.copies=='7' and t.ids=='6','P6: the shape block is still shown in full',
  facts(t,{'observed','status','copies','ids'}))
 A.LockedShapeView=function() error('ZQ_SHAPE_THROW_MARKER',0) end
 local ok2,text2=T.realPcall(T.prepared)
 A.LockedShapeView=realShape
 guard(ok2,'P6: the report is prepared while the shape accessor fails',text2)
 text2=ok2 and text2 or ''
 local o=T.tokens(T.lines(text2,'Ownership sample'))
 guard(o['locked.observed']=='yes' and o['locked.rejection']=='over_cap' and o['locked.copies']=='7',
  'P6: the ownership sample block is unchanged by a failing shape accessor',facts(o,{'locked.observed','locked.rejection','locked.copies'}))
 guard(#T.lines(text2,'Orb readiness')>0,'P6: and the Orb readiness block is kept')
 local f=T.shapeBlock(text2)
 expect(f.observed=='unavailable' or f.observed=='unknown','P6: the failing shape accessor is shown as unavailable',f.observed)
end)

T.finish('locked_shape_report')
