-- Alignment probe (P-ALIGN-1) for the first full-run failure of
-- catalog_idle_frames (checks/m5-released-peer-full-01: catalog_idle_frames.lua:113,
-- "fixture: the write committed inside the preparation window"; cause NOT
-- ESTABLISHED, not waived). Observation only: no remedy and no new behaviour.
--
-- Source adjudication found that between the second Put and the end of the
-- preparation-window loop no other production owner can settle ticket2, so
-- its fate is set by the state at the second Put. In that sequence the
-- real-clock-dependent part is how many frames pass before it, which sets the
-- phase of the synthetic-time owners (DataCompaction, DataRetention retries,
-- Scheduler tasks). This probe varies that alignment on purpose and records
-- how ticket2 settles, with the state around it.
--
-- One row per k in KS. Each row is a fresh in-process boot (the inherited
-- module-reload pattern of startup_persistence.lua): default real-clock pacing,
-- T.Profile(40,60), and then catalog_idle_frames.lua lines 14-117 in the same
-- order, with the same profile, frame counts, counting wrappers, ticket-1
-- loop, store-slice wrapper (rawStore, then raw PumpRootAdmission while pending,
-- guard 100000) and +5 ms profiler offset. The only change to that order is k
-- extra idle H.Advance(.05) frames between original lines 70 and 72. Inside the
-- window only a wrapper-entered count, the ticket state at entry and the loop
-- iteration count are kept: no status read, clock read or allocation in the
-- loop. Everything else is read between frames, outside the window.
--
-- Categories (view_regression_support): SETUP is a per-row fixture or
-- instrument condition; an unmet one is reported as SETUP_UNMET_<which> for
-- that row only and the later rows still run (a SETUP failure is a limit to
-- investigate, not a behavioural negative). GUARD is the original post-window
-- behaviour (:114, :117) and the original :87 idle property, evaluated only on
-- rows whose ticket2 committed. No EXPECT. A row whose ticket2 did not commit
-- is a FINDING: it is printed with its state, reason, detail and owner
-- context and is not asserted. Controls: k=0 is the positive control
-- (expected COMMITTED; reported, not asserted). A separate k=0 boot calls the
-- public CancelRootAdmission after the second Put: a CONTROL, not a production
-- mechanism, expected to be recorded as FAILED_CANCELLED with zero loop
-- iterations (no pending ticket at wrapper entry, by design). Its validity is a
-- SETUP check of the instrument.
--
-- Limits. In-process reboots share the Lua allocator and GC with earlier rows;
-- real-clock pacing still varies per row, so rows are self-describing, not
-- exactly reproducible. Observation between frames allocates and can shift
-- pacing. A PASS describes this k-range on this machine only: it is not
-- acceptance, not a waiver of the historical red and not a global disproof of
-- any cause. A finding is a candidate observation; repeating it requires a
-- separate root binding (this file has no retry). Synthetic services only; no
-- native claim.
local T=dofile('tests/prototype/startup_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local P=V.Checker('catalog_idle_frames_alignment_probe')

local KS={0,1,2,3,5,8,13,21,34,55,89,144,233,377}

local function fmt(v)
 local t=type(v)
 if t=='nil' or t=='boolean' then return tostring(v) end
 if t=='number' then
  if v~=v or v==math.huge or v==-math.huge then return tostring(v) end
  return (v==math.floor(v) and math.abs(v)<2^53 and string.format('%d',v) or string.format('%.3f',v))
 end
 if t=='string' then return (v:gsub('[%c]',' ')) end
 return '<'..t..'>'
end
-- One level of a table, scalars only, sorted by key (for a ticket detail).
local function Shallow(v)
 if type(v)~='table' then return fmt(v) end
 local items={}
 for key,value in pairs(v) do items[#items+1]={tostring(key),value} end
 table.sort(items,function(a,b) return a[1]<b[1] end)
 local parts={}
 for i,item in ipairs(items) do
  if i>16 then parts[#parts+1]='...';break end
  parts[#parts+1]=item[1]..':'..(type(item[2])=='table' and '<table>' or fmt(item[2]))
 end
 return '{'..table.concat(parts,',')..'}'
end
local function emit(row,section,fields)
 local parts={'PROBE',row.label,section}
 for _,kv in ipairs(fields) do parts[#parts+1]=kv[1]..'='..fmt(kv[2]) end
 print(table.concat(parts,'\t'))
end
local function append(list,more) for _,kv in ipairs(more) do list[#list+1]=kv end return list end

-- Passive readers, used only between frames.
local function Prep(fn)
 local ok,s=pcall(fn)
 if not ok or type(s)~='table' then return {error=tostring(s)} end
 return s
end
local function PrepFields(prefix,s)
 return {{prefix..'ready',s.ready},{prefix..'relevant',s.relevant},{prefix..'ownerAgrees',s.ownerAgrees},
  {prefix..'reason',s.reason or s.error},{prefix..'kind',s.kind},{prefix..'phase',s.phase},{prefix..'pumps',s.pumps},
  {prefix..'totalPumps',s.totalPumps},{prefix..'binding',s.binding},{prefix..'generation',s.generation}}
end
local DEBUG_KEYS={'rootPumps','rootAdmissions','driftInvalidations','protectedFailures','commits','putCalls',
 'putChanges','bundleWrites','servingSwaps','maintenanceCommits','mutationCompletionFailures','rebinds','initCalls',
 'notificationFailures'}
local function DebugSubset(C)
 local ok,s=pcall(C.DebugStats)
 if not ok or type(s)~='table' then return {error=tostring(s)} end
 local out={}
 for _,key in ipairs(DEBUG_KEYS) do out[key]=s[key] end
 return out
end
local function DebugFields(prefix,now,ref)
 local out={}
 for _,key in ipairs(DEBUG_KEYS) do
  local v=now[key]
  if ref then v=(tonumber(now[key]) and tonumber(ref[key])) and now[key]-ref[key] or nil end
  out[#out+1]={prefix..key,v}
 end
 if now.error then out[#out+1]={prefix..'error',now.error} end
 return out
end
local function CoordinatorFields(prefix,coord)
 if type(coord)~='table' then return {{prefix..'coordinator','absent'}} end
 local r=type(coord.result)=='table' and coord.result or {}
 local m=type(coord.mutation)=='table' and coord.mutation or nil
 return {{prefix..'state',coord.state},{prefix..'result',r.state},{prefix..'resultDetail',r.result or r.reason},
  {prefix..'mutationRoute',m and m.route or 'none'},{prefix..'maintenanceStarted',coord.automaticMaintenanceStarted==true}}
end
local function OwnerFields(prefix)
 local out={}
 local comp=Nexus.DataCompaction
 if comp and type(comp.Stats)=='function' then
  local ok,s=pcall(comp.Stats,NexusDB)
  s=ok and type(s)=='table' and s or {}
  append(out,{{prefix..'compactionPending',s.pending},{prefix..'compactionPhase',s.phase},
   {prefix..'compactionPumps',s.pumps},{prefix..'compactionRestarts',s.restarts},
   {prefix..'compactionMigrationVersion',s.migrationVersion}})
 end
 local ret=Nexus.DataRetention
 if ret and type(ret.Stats)=='function' then
  local ok,s=pcall(ret.Stats,NexusDB)
  out[#out+1]={prefix..'retentionLastRun',ok and type(s)=='table' and 'present' or 'none'}
 end
 local sch=Nexus.Scheduler
 if sch and type(sch.Pending)=='function' then
  local ok,list=pcall(sch.Pending)
  local keys={}
  if ok and type(list)=='table' then
   for _,task in ipairs(list) do keys[#keys+1]=tostring(task.key)..'@'..fmt(tonumber(task.due)) end
  end
  append(out,{{prefix..'schedulerTasks',#keys},{prefix..'schedulerDue',table.concat(keys,',')}})
 end
 local ev=Nexus.LoadoutEvidence
 if ev and type(ev.CandidateOpen)=='function' then
  local ok,open=pcall(ev.CandidateOpen)
  local value='error'
  if ok then value=open end
  out[#out+1]={prefix..'evidenceCandidateOpen',value}
 end
 return out
end
local function TimingFields(prefix)
 local st=Nexus.startupTiming or {}
 local mt=Nexus.manualSyncTiming or {}
 return {{prefix..'startupUpdates',st.updates},{prefix..'startupSlices',st.slices},
  {prefix..'startupOvershoots',st.overshoots},{prefix..'driveSlices',mt.driveSlices or 0},
  {prefix..'driveOvershoots',mt.driveOvershoots or 0},{prefix..'driveMaxBatchMs',mt.driveMaxBatchMs or 0},
  {prefix..'driveFallbackUpdates',mt.driveFallbackUpdates or 0}}
end

-- Which source owner a finding points at (owner names only; the reports cite lines).
local OWNERS={
 SOURCE_DRIFT='BuildCatalog TokenDrifted or the mutation-bundle source verification (PumpAdmission)',
 SOURCE_WITNESS_MISSING='BuildCatalog mutation-bundle source verification (PumpAdmission)',
 FRONTIER_NO_PROGRESS='BuildCatalog PumpAdmission (a pending pump charged no work)',
 PROTECTED_COMMIT_FAILED='BuildCatalog PublishRoot protected section (CommitDurableBundle or serving swap)',
 ROOT_PUBLICATION_FAILED='BuildCatalog PumpAdmission pcall(PublishRoot)',
 PUBLICATION_SOURCE_CHANGED='BuildCatalog PublishRoot publication guard',
 SAVED_FORMAT_READ_ONLY='BuildCatalog PublishRoot read-only saved root',
 CANCELLED='BuildCatalog CancelRootAdmission',
 SUPERSEDED='BuildCatalog BeginRootAdmission (a new admission replaced the mutation)',
 GENERATION_EXHAUSTED='BuildCatalog generation latch',
}
local function OwnerOf(class,ticket2)
 if class=='WRAPPER_NOT_ENTERED' then return 'MainLifecycle RunUpdate did not reach PumpStoreMutationSlice in the window advance' end
 if class=='PENDING_AFTER_GUARD' then return 'BuildCatalog PumpRootAdmission/PumpAdmission: 100000 raw pumps without settlement' end
 if class=='ADVANCE_RAISED' then return 'an error was raised inside the window advance (see advanceError)' end
 if class:find('^NO_LOOP_TICKET_') then
  return 'ticket2 was not pending at wrapper entry: settled after the second Put and before the store slice'
 end
 local reason=ticket2 and ticket2.reason
 return OWNERS[reason] or 'BuildCatalog AdmissionFail in a preparation, bundle, witness or index phase (see ticket2Detail)'
end
local function Classify(advanced,trace,ticket2)
 if not advanced then return 'ADVANCE_RAISED' end
 if trace.entered==0 then return 'WRAPPER_NOT_ENTERED' end
 if trace.iterations==0 then return 'NO_LOOP_TICKET_'..tostring(trace.stateAtEntry) end
 if ticket2.state=='committed' then return 'COMMITTED' end
 if ticket2.state=='failed' then return 'FAILED_'..tostring(ticket2.reason) end
 if ticket2.state=='pending' then
  return trace.iterations>=100000 and 'PENDING_AFTER_GUARD' or 'PENDING_UNEXPLAINED'
 end
 return 'UNCLASSIFIED_'..tostring(ticket2.state)
end

local function upvalue(fn,name)
 if type(fn)~='function' then return nil end
 for i=1,255 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==name then return v end end
end

-- A fresh runtime state in this process, as startup_persistence.lua does it:
-- the module globals are cleared and the harness and every runtime file are
-- loaded again. Then original lines 14-17.
local function Boot()
 Nexus=nil;NexusDB=nil;NexusSupportDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 local H=dofile('tests/prototype/harness.lua')
 NexusDB=T.Profile(40,60);T.Load()
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 local readyFrames=T.Until(H,function()return Nexus.StartupStatus().state=='ready'end,200000)
 for _=1,100 do H.Advance(.05) end
 return H,readyFrames
end

local function Row(row)
 local k,control=row.k,row.control
 local L=row.label..': '
 local restore
 local function unmet(which,detail)
  row.class='SETUP_UNMET_'..which
  if restore then restore() end
  emit(row,'result',{{'class',row.class},{'detail',detail},
   {'note','fixture or instrument limit for this row; not a behavioural negative'}})
 end
 local okBoot,H,readyFrames=pcall(Boot)
 if not P.setup(okBoot,L..'fixture: a fresh boot reaches ready',not okBoot and H or nil) then
  unmet('BOOT_READY',H);return
 end
 -- Original lines 18-20.
 local C=Nexus.BuildCatalog
 local count=C.Count();local countText=C.Count()
 local admitted=count==40 and C.RootState().state=='ROOT_ADMITTED' and C.RootState().candidate==false
 if not P.setup(admitted,L..'fixture: the saved catalog is admitted and idle: '..tostring(countText)) then
  unmet('CATALOG_ADMITTED',countText);return
 end
 -- Original lines 22-33.
 local frame
 for _,f in ipairs(H.frames) do local s=f.scripts.OnUpdate;if s and upvalue(s,'Lifecycle') then frame=f end end
 local lifecycle=frame and upvalue(frame.scripts.OnUpdate,'Lifecycle')()
 local runUpdate=lifecycle and upvalue(upvalue(lifecycle.OnUpdate,'OnUpdate'),'RunUpdate')
 local batch=runUpdate and upvalue(runUpdate,'PumpCatalogAdmissionBatch')
 local slice=batch and upvalue(batch,'PumpCatalogRootAdmissionSlice')
 if not P.setup(type(batch)=='function' and type(slice)=='function',L..'the lifecycle admission batch and slice are found') then
  unmet('LIFECYCLE_HOOKS');return
 end
 -- Original lines 35-53: the same counting wrappers.
 local calls={status=0,root=0,pump=0}
 local wrapped={ManualPreparationStatus='status',RootState='root',PumpRootAdmission='pump'}
 local raw={}
 for name,key in pairs(wrapped) do
  raw[name]=C[name]
  C[name]=function(...)
   local caller=debug.getinfo(2,'f')
   local mine=key=='pump' or (key=='status' and caller and caller.func==batch)
    or (key=='root' and caller and caller.func==slice)
   if mine then calls[key]=calls[key]+1 end
   return raw[name](...)
  end
 end
 restore=function() for name in pairs(wrapped) do C[name]=raw[name] end end
 local function Frames(n)
  for key in pairs(calls) do calls[key]=0 end
  for _=1,n do H.Advance(.05) end
 end
 -- Original lines 55-70, the same actions; their values are recorded, not asserted.
 Frames(40)
 local s1={pump=calls.pump,root=calls.root,status=calls.status}
 local status=Nexus.StartupStatus()
 s1.ready=status.syncGateCatalogReady==true
 local timing=Nexus.manualSyncTiming
 s1.observed=timing.catalogPhase==nil and timing.catalogKind==nil and timing.catalogPumps==0 and timing.catalogWork==0
 timing.catalogPhase,timing.catalogKind,timing.catalogPumps,timing.catalogWork='rows','mutation',7,9
 H.Advance(.05)
 s1.replaced=timing.catalogPhase==nil and timing.catalogKind==nil and timing.catalogPumps==0 and timing.catalogWork==0
 -- P-ALIGN-1: the only change to the original order. k extra idle frames
 -- between original lines 70 and 72; nothing else is called in them.
 for key in pairs(calls) do calls[key]=0 end
 for _=1,k do H.Advance(.05) end
 local align={pump=calls.pump,root=calls.root,now=H.now}
 -- Original lines 72-88.
 local donor=C.Get('synthetic-startup-7')
 if not P.setup(donor~=nil,L..'fixture: a stored build to copy') then unmet('DONOR');return end
 local record=H.Clone(donor);record.id='received-idle-1';record.title='Received idle';record.author='Remote-Realm'
 local before=C.Count()
 local ok,why,ticket=C.Put(record)
 if not P.setup(ok==nil and why=='ROOT_MUTATION_PENDING' and type(ticket)=='table',
  L..'fixture: the first write starts a catalog mutation: '..tostring(why)) then
  unmet('TICKET1_PENDING',why);return
 end
 for key in pairs(calls) do calls[key]=0 end
 local frames=0
 while ticket.state=='pending' and frames<4000 do H.Advance(.05);frames=frames+1 end
 if not P.setup(ticket.state=='committed',L..'fixture: the first write commits: '..tostring(ticket.state)..' after '..frames..' frames') then
  unmet('TICKET1_COMMITTED',tostring(ticket.state)..'/'..tostring(ticket.reason));return
 end
 local s2={frames=frames}
 local count1=C.Count()
 s2.stored=count1==before+1 and C.Get('received-idle-1')~=nil
 s2.countText=C.Count()
 s2.pumps=calls.pump
 Frames(20)
 s2.idlePump,s2.idleRoot=calls.pump,calls.root
 s2.ready=Nexus.StartupStatus().syncGateCatalogReady==true and timing.catalogKind==nil
 -- Original lines 94-97.
 local storeIndex,rawStore
 for i=1,255 do local n,v=debug.getupvalue(runUpdate,i);if not n then break end
  if n=='PumpStoreMutationSlice' then storeIndex,rawStore=i,v end end
 if not P.setup(storeIndex~=nil,L..'fixture: the lifecycle store slice is found') then unmet('STORE_SLICE');return end
 -- State before the second Put (reads only; the Store coordinator through the
 -- raw slice's own upvalue, as the session-17 witness reads it).
 local coord=upvalue(rawStore,'bootstrapCoordinator')
 emit(row,'beforePut2',append(append(append(append({{'k',k},{'now',H.now},{'readyFrames',readyFrames},
  {'alignNow',align.now},{'alignPumps',align.pump},{'alignRootReads',align.root},
  {'section1.pumps',s1.pump},{'section1.rootReads',s1.root},{'section1.statusReads',s1.status},
  {'section1.ready',s1.ready},{'section1.observed',s1.observed},{'section1.replaced',s1.replaced},
  {'ticket1.frames',s2.frames},{'ticket1.stored',s2.stored},{'ticket1.count',s2.countText},
  {'ticket1.pendingPumps',s2.pumps},{'ticket1.idlePumps',s2.idlePump},{'ticket1.idleRootReads',s2.idleRoot},
  {'ticket1.idleReady',s2.ready},{'rebindRequired',C.RebindRequired()}},
  CoordinatorFields('store.',coord)),OwnerFields('')),TimingFields('')),DebugFields('',DebugSubset(C))))
 -- Original lines 98-100.
 local second=H.Clone(donor);second.id='received-idle-2';second.title='Received idle 2';second.author='Remote-Realm'
 local ok2,why2,ticket2=C.Put(second)
 if not P.setup(ok2==nil and why2=='ROOT_MUTATION_PENDING' and type(ticket2)=='table',
  L..'fixture: a second write is pending: '..tostring(why2)) then
  unmet('TICKET2_PENDING',why2);return
 end
 local agreesAtPut,bindingAtPut,bindingReasonAtPut=C.SourceBinding()
 emit(row,'atPut2',append({{'ticket2State',ticket2.state},{'ticket2Pumps',ticket2.pumps},
  {'sourceAgrees',agreesAtPut},{'bindingGeneration',bindingAtPut},{'bindingReason',bindingReasonAtPut},
  {'rebindRequired',C.RebindRequired()}},PrepFields('prep.',Prep(raw.ManualPreparationStatus))))
 if control then
  -- CONTROL only: a public API call that settles ticket2 failed. It shows the
  -- probe records a failed ticket and its reason; it is not a mechanism.
  local cancelled=C.CancelRootAdmission()
  emit(row,'control',{{'action','CancelRootAdmission (public API; CONTROL, not a production mechanism)'},
   {'rootState',type(cancelled)=='table' and cancelled.state or nil},
   {'rootReason',type(cancelled)=='table' and cancelled.reason or nil},
   {'ticket2State',ticket2.state},{'ticket2Reason',ticket2.reason}})
 end
 -- Original lines 101-112: the same clock replacement, wrapper, loop, guard
 -- and offset. Inside it only the trace fields below are written.
 local realClock,offset=debugprofilestop,0
 if not P.setup(type(realClock)=='function',L..'fixture: a profiler clock') then unmet('PROFILER_CLOCK');return end
 local debugBefore=DebugSubset(C)
 debugprofilestop=function() return realClock()+offset end
 local trace={entered=0,iterations=0,stateAtEntry=false}
 debug.setupvalue(runUpdate,storeIndex,function(...)
  trace.entered=trace.entered+1;trace.stateAtEntry=ticket2.state
  rawStore(...)
  local guard=0
  while ticket2.state=='pending' and guard<100000 do raw.PumpRootAdmission();guard=guard+1 end
  trace.iterations=guard
  offset=offset+5
 end)
 local advanced,advanceError=pcall(H.Advance,.05)
 debug.setupvalue(runUpdate,storeIndex,rawStore)
 debugprofilestop=realClock
 -- Original :114, read at once (two calls, as the original makes them).
 local gateAfter=Nexus.StartupStatus().syncGateCatalogReady
 local gateText=tostring(Nexus.StartupStatus().syncGate)
 local debugAfter=DebugSubset(C)
 local agreesAfter,bindingAfter,bindingReasonAfter=C.SourceBinding()
 local class=Classify(advanced,trace,ticket2)
 local resultFields={{'ticket2State',ticket2.state},{'ticket2Committed',ticket2.committed},
  {'ticket2Reason',ticket2.reason},{'ticket2Detail',Shallow(ticket2.detail)},{'ticket2Pumps',ticket2.pumps},
  {'wrapperEntered',trace.entered},{'stateAtWrapperEntry',trace.stateAtEntry},{'loopIterations',trace.iterations},
  {'advanced',advanced},{'advanceError',advanced and 'none' or tostring(advanceError)},
  {'syncGateCatalogReadyAfter',gateAfter},{'syncGateAfter',gateText},
  {'rebindRequiredAfter',C.RebindRequired()},{'sourceAgreesAfter',agreesAfter},
  {'bindingGenerationAfter',bindingAfter},{'bindingReasonAfter',bindingReasonAfter}}
 if control then
  local valid=advanced==true and ticket2.state=='failed' and ticket2.reason=='CANCELLED' and ticket2.committed==false
  row.class=valid and 'CONTROL_FAILED_CANCELLED' or ('CONTROL_INVALID_'..class)
  row.controlValid=valid
  emit(row,'result',append(append(append({{'class',row.class},{'controlValid',valid},
   {'expected','CONTROL_FAILED_CANCELLED: wrapperEntered=1, stateAtWrapperEntry=failed, loopIterations=0 by design'}},
   resultFields),DebugFields('delta.',debugAfter,debugBefore)),OwnerFields('after.')))
  P.setup(valid,'CONTROL cancellation: the probe records FAILED_CANCELLED after a public CancelRootAdmission',
   row.class..' '..tostring(ticket2.state)..'/'..tostring(ticket2.reason))
  restore()
  if not advanced then error(advanceError,0) end
  return
 end
 row.class=class
 local finding=class~='COMMITTED'
 emit(row,'result',append(append(append({{'class',class},{'finding',finding},
  {'owner',finding and OwnerOf(class,ticket2) or nil},
  {'note',finding and 'observation only, not asserted as a behavioural negative; a deterministic repeat needs a separate root binding' or nil}},
  resultFields),DebugFields('delta.',debugAfter,debugBefore)),OwnerFields('after.')))
 if not advanced then restore();error(advanceError,0) end
 -- Original lines 113-117 and the original :87 idle property, only where
 -- ticket2 committed.
 if class=='COMMITTED' then
  P.guard(gateAfter==false,L..'over the allowance: not reported ready in this update (original :114): '..gateText)
  H.Advance(.05)
  P.guard(Nexus.StartupStatus().syncGateCatalogReady==true,L..'the next update reports the catalog ready (original :117)')
  Frames(20)
  P.guard(calls.pump==0 and calls.root==0,
   L..'after the second commit the frames are idle again (original :87 property): '..calls.pump..' '..calls.root)
 end
 -- Original line 119.
 restore()
end

local results={}
local function Run(k,control)
 local row={k=k,control=control==true,label=control and 'control-cancel-k0' or ('k='..k)}
 results[#results+1]=row
 local ok=P.scenario('alignment row '..row.label,function() Row(row) end)
 if not ok then
  row.class=row.class or 'RAISED'
  emit(row,'raised',{{'class',row.class}})
 end
 return row
end

local rows={}
for _,k in ipairs(KS) do rows[#rows+1]=Run(k,false) end
local cancel=Run(0,true)

-- Summary. Findings are counted and named here; they are not assertions.
local counts,order,findingRows,unmetRows,raisedRows={},{},{},{},{}
for _,row in ipairs(rows) do
 local class=row.class or 'RAISED'
 if not counts[class] then counts[class]=0;order[#order+1]=class end
 counts[class]=counts[class]+1
 if class:find('^SETUP_UNMET_') then unmetRows[#unmetRows+1]=row.label
 elseif class=='RAISED' then raisedRows[#raisedRows+1]=row.label
 elseif class~='COMMITTED' then findingRows[#findingRows+1]=row.label..':'..class end
end
table.sort(order)
local classParts={}
for _,class in ipairs(order) do classParts[#classParts+1]=class..':'..counts[class] end
local positive=rows[1]
local positiveValid=positive.class=='COMMITTED'
local cancelValid=cancel.controlValid==true
local interpretable=positiveValid and cancelValid and #unmetRows==0 and #raisedRows==0
local summaryRow={label='summary'}
emit(summaryRow,'rows',{{'rows',#rows},{'classes',table.concat(classParts,',')},{'findings',#findingRows},
 {'findingRows',table.concat(findingRows,',')},{'setupUnmet',#unmetRows},{'setupUnmetRows',table.concat(unmetRows,',')},
 {'raised',#raisedRows},{'raisedRows',table.concat(raisedRows,',')}})
print(table.concat({'CONTROL','positive','k=0','expected=COMMITTED','observed='..fmt(positive.class),
 'valid='..tostring(positiveValid)},'\t'))
print(table.concat({'CONTROL','cancellation','k=0','expected=CONTROL_FAILED_CANCELLED','observed='..fmt(cancel.class),
 'valid='..tostring(cancelValid)},'\t'))
local meaning
if not interpretable then
 meaning='NOT_INTERPRETABLE: a control or fixture condition did not hold; no mechanism conclusion'
elseif #findingRows>0 then
 meaning='FINDINGS_PRESENT: candidate observations only, not the historical cause; a deterministic repeat of each finding row needs root binding'
else
 meaning='ALL_ALIGNMENTS_COMMITTED_SCOPE_LIMITED: no failing branch in this k-range, machine and in-process boot sequence; not acceptance, not a waiver, cause NOT_ESTABLISHED'
end
emit(summaryRow,'interpretation',{{'interpretable',interpretable},{'meaning',meaning}})

P.finish('(observation probe: '..#findingRows..' finding row(s); a PASS is not acceptance and does not explain the historical first red; synthetic services, no native claim)')
