-- Cause witness for the first full-run failure of catalog_idle_frames
-- (checks/m5-released-peer-full-01: 529 PASS / 1 FAIL, catalog_idle_frames.lua:113,
-- "fixture: the write committed inside the preparation window"; cause NOT
-- ESTABLISHED). That row shows only that ticket2 was not committed: it does
-- not say whether the store-slice wrapper ran, whether the ticket was still
-- pending or failed and why, or what the lifecycle and profiler did.
--
-- This file replays catalog_idle_frames.lua lines 11-117 in the same order,
-- with the same profile, limits, frame counts, counting wrappers, store-slice
-- wrapper, loop guard and +5 ms profiler offset, and the same assertions, and
-- adds only passive observation:
--  C1  the one failing advance: event-frame OnUpdate dispatch (a delegating
--      wrapper for that advance only), lifecycle initialization, wrapper
--      entry/exit, the raw Store slice returning, catalog loop iterations;
--  C2  ticket2 state/reason/pumps at entry and at the end, each raw pump
--      outcome, candidate phase transitions (ManualPreparationStatus, a read),
--      admission pumps made by other callers in that frame;
--  C3  Store coordinator state/result/mutation route, rebind request, source
--      binding, bound database, and the identities TokenDrifted compares,
--      against their values at the Put;
--  C4  every profiler reading in that frame (the test's own replacement
--      clock), tagged before/in/after the wrapper, synthetic H.now apart from
--      real time, PreparationPumpCount at frame start and wrapper exit (so the
--      batch's priorSlices), manualSyncTiming drive deltas, Performance
--      aggregates, and the Sync gate it decided;
--  C5  the original :113 (SETUP), :114 and :117 (GUARD), then, after the
--      original sequence, the served/durable publication of the second build
--      and zero idle admission work.
-- Every observation is printed at once as a WITNESS line, so a later raise
-- keeps what was seen. C.RootState() is called only where the original calls
-- it (it can invalidate on drift); every other read used here mutates nothing.
--
-- Categories (view_regression_support): SETUP is a condition the failing
-- frame depends on, including the original :113 (its own message calls it a
-- fixture); GUARD is the original test's behaviour and its effects, which
-- must keep holding. No EXPECT: this witness asserts no new behaviour.
--
-- Limits. The observation adds calls, allocations and printing between
-- frames and inside the failing frame, so real-clock pacing and GC timing are
-- not those of the historical run; the overhead inside the frame is measured
-- and printed. A PASS describes one healthy run and does not explain the
-- historical red. A red prints the branch that was reached; by itself it is
-- not proof of the historical cause. Synthetic services; no native claim.
local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local W=V.Checker('catalog_idle_frames_witness')
-- The harness profiler, read directly only to time the observation itself
-- (never through the global the lifecycle reads, so no production reading is
-- added). Without it the overhead is reported as 0, not measured.
local wallClock=type(debugprofilestop)=='function' and debugprofilestop or function() return 0 end
local observerMs=0

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
local function emit(section,fields)
 local parts={'WITNESS',section}
 for _,kv in ipairs(fields) do parts[#parts+1]=kv[1]..'='..fmt(kv[2]) end
 print(table.concat(parts,'\t'))
end
local function append(list,more) for _,kv in ipairs(more) do list[#list+1]=kv end return list end
local function Prep(fn)
 local ok,s=pcall(fn)
 if not ok or type(s)~='table' then return {error=tostring(s)} end
 return s
end
local function PrepFields(prefix,s)
 return {{prefix..'ready',s.ready},{prefix..'relevant',s.relevant},{prefix..'ownerAgrees',s.ownerAgrees},
  {prefix..'reason',s.reason or s.error},{prefix..'kind',s.kind},{prefix..'phase',s.phase},{prefix..'pumps',s.pumps},
  {prefix..'totalPumps',s.totalPumps},{prefix..'work',s.work},{prefix..'row',s.row},{prefix..'index',s.index},
  {prefix..'witnessRoot',s.witnessRoot},{prefix..'witnessDepth',s.witnessDepth},
  {prefix..'binding',s.binding},{prefix..'generation',s.generation}}
end
local function DebugSubset(C)
 local ok,s=pcall(C.DebugStats)
 if not ok or type(s)~='table' then return {error=tostring(s)} end
 return {rootPumps=s.rootPumps,rootAdmissions=s.rootAdmissions,driftInvalidations=s.driftInvalidations,
  protectedFailures=s.protectedFailures,commits=s.commits,putCalls=s.putCalls,putChanges=s.putChanges,
  bundleWrites=s.bundleWrites,servingSwaps=s.servingSwaps,maintenanceCommits=s.maintenanceCommits,
  mutationCompletionFailures=s.mutationCompletionFailures,rebinds=s.rebinds,initCalls=s.initCalls,
  notificationFailures=s.notificationFailures}
end
local DEBUG_KEYS={'rootPumps','rootAdmissions','driftInvalidations','protectedFailures','commits','putCalls',
 'putChanges','bundleWrites','servingSwaps','maintenanceCommits','mutationCompletionFailures','rebinds','initCalls',
 'notificationFailures'}
local function DebugFields(prefix,now,ref)
 local out={}
 for _,k in ipairs(DEBUG_KEYS) do
  local v=now[k]
  if ref then v=(tonumber(now[k]) and tonumber(ref[k])) and now[k]-ref[k] or nil end
  out[#out+1]={prefix..k,v}
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
local function Identities()
 local db=NexusDB
 local ev=Nexus.LoadoutEvidence
 local okToken,tok=false,nil
 if ev and type(ev.AuthorityTokenV1)=='function' then okToken,tok=pcall(ev.AuthorityTokenV1) end
 tok=okToken and type(tok)=='table' and tok or {}
 return {db=db,bundle=type(db)=='table' and rawget(db,'authorityBundle') or nil,revisions=Nexus.Revisions,
  evidence=ev,evidenceOwner=tok.ownerIdentity,append=tok.appendRevision,removal=tok.removalRevision,
  provider=tok.providerRevision,bundled=Nexus.BundledBuilds}
end
local function IdentityFields(prefix,now,ref)
 return {{prefix..'sameDb',now.db==ref.db},{prefix..'sameBundle',now.bundle==ref.bundle},
  {prefix..'sameRevisionsOwner',now.revisions==ref.revisions},
  {prefix..'sameEvidenceOwner',now.evidence==ref.evidence and now.evidenceOwner==ref.evidenceOwner},
  {prefix..'evidenceAppend',now.append},{prefix..'evidenceRemoval',now.removal},{prefix..'evidenceProvider',now.provider},
  {prefix..'sameBundledBuilds',now.bundled==ref.bundled}}
end
local function TimingSnapshot()
 local st=Nexus.startupTiming or {}
 local mt=Nexus.manualSyncTiming or {}
 return {startupUpdates=st.updates,startupSlices=st.slices,startupMaxBatchMs=st.maxBatchMs,
  startupOvershoots=st.overshoots,startupFallbackUpdates=st.fallbackUpdates,communityMaxMs=st.communityMaxMs,
  driveSlices=mt.driveSlices or 0,driveMaxBatchMs=mt.driveMaxBatchMs or 0,driveOvershoots=mt.driveOvershoots or 0,
  driveFallbackUpdates=mt.driveFallbackUpdates or 0}
end
local TIMING_KEYS={'startupUpdates','startupSlices','startupMaxBatchMs','startupOvershoots','startupFallbackUpdates',
 'communityMaxMs','driveSlices','driveMaxBatchMs','driveOvershoots','driveFallbackUpdates'}
local function TimingFields(prefix,now)
 local out={}
 for _,k in ipairs(TIMING_KEYS) do out[#out+1]={prefix..k,now[k]} end
 return out
end
local PERF={'lifecycle.update','lifecycle.phase.store','lifecycle.phase.maintenance','lifecycle.phase.catalog'}
local function Perf()
 local p=Nexus.Performance
 local out={}
 for _,name in ipairs(PERF) do
  local ok,s=false,nil
  if p and type(p.Stats)=='function' then ok,s=pcall(p.Stats,name) end
  out[name]=ok and type(s)=='table' and s or {count=0,last=0}
 end
 return out
end
local function OwnerFields()
 local out={}
 local comp=Nexus.DataCompaction
 if comp and type(comp.Stats)=='function' then
  local ok,s=pcall(comp.Stats,NexusDB)
  s=ok and type(s)=='table' and s or {}
  append(out,{{'compactionPending',s.pending},{'compactionPhase',s.phase},{'compactionPumps',s.pumps},
   {'compactionMigrationVersion',s.migrationVersion}})
 end
 local ret=Nexus.DataRetention
 if ret and type(ret.Stats)=='function' then
  local ok,s=pcall(ret.Stats,NexusDB)
  out[#out+1]={'retentionLastRun',ok and type(s)=='table' and 'present' or 'none'}
 end
 local sch=Nexus.Scheduler
 if sch and type(sch.Pending)=='function' then
  local ok,list=pcall(sch.Pending)
  local keys={}
  if ok and type(list)=='table' then
   for _,task in ipairs(list) do keys[#keys+1]=tostring(task.key)..'@'..fmt(tonumber(task.due)) end
  end
  append(out,{{'schedulerTasks',#keys},{'schedulerDue',table.concat(keys,',')}})
 end
 return out
end

W.scenario('replay of catalog_idle_frames lines 11-117 with passive observation',function()
 -- Original lines 14-20.
 NexusDB=T.Profile(40,60);T.Load()
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 local readyFrames=T.Until(H,function()return Nexus.StartupStatus().state=='ready'end,200000)
 local readyAt=H.now
 for _=1,100 do H.Advance(.05) end
 local C=Nexus.BuildCatalog
 W.setup(C.Count()==40,'fixture: the saved catalog is admitted: '..C.Count())
 W.setup(C.RootState().state=='ROOT_ADMITTED' and C.RootState().candidate==false,'fixture: the catalog is admitted and idle')
 emit('boot',append(append(append({{'readyFrames',readyFrames},{'readyAt',readyAt},{'now',H.now},
  {'rebindRequired',C.RebindRequired()}},TimingFields('',TimingSnapshot())),OwnerFields()),DebugFields('',DebugSubset(C))))

 -- Original lines 22-53.
 local function upvalue(fn,name)
  for i=1,255 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==name then return v end end
 end
 local frame
 for _,f in ipairs(H.frames) do local s=f.scripts.OnUpdate;if s and upvalue(s,'Lifecycle') then frame=f end end
 local lifecycle=frame and upvalue(frame.scripts.OnUpdate,'Lifecycle')()
 local runUpdate=lifecycle and upvalue(upvalue(lifecycle.OnUpdate,'OnUpdate'),'RunUpdate')
 local batch=runUpdate and upvalue(runUpdate,'PumpCatalogAdmissionBatch')
 W.setup(type(batch)=='function','the lifecycle admission batch is found')
 local slice=upvalue(batch,'PumpCatalogRootAdmissionSlice')
 W.setup(type(slice)=='function','the lifecycle admission slice is found')
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
 local function Frames(n)
  for k in pairs(calls) do calls[k]=0 end
  for _=1,n do H.Advance(.05) end
 end

 -- Original section 1, lines 55-70.
 Frames(40)
 W.guard(calls.pump==0,'idle: no admission slice (test.9053: one per frame): '..calls.pump..' in 40 frames')
 W.guard(calls.root==0,'idle: no root-state read (test.9053: one per frame): '..calls.root)
 W.guard(calls.status==40,'idle: the batch reads the status once per frame (test.9053: three): '..calls.status)
 local status=Nexus.StartupStatus()
 W.guard(status.syncGateCatalogReady==true,'Sync sees the catalog ready: '..tostring(status.syncGate))
 local timing=Nexus.manualSyncTiming
 W.guard(timing.catalogPhase==nil and timing.catalogKind==nil and timing.catalogPumps==0 and timing.catalogWork==0,
  'the idle observation is recorded: '..tostring(timing.catalogKind)..' '..tostring(timing.catalogPumps))
 timing.catalogPhase,timing.catalogKind,timing.catalogPumps,timing.catalogWork='rows','mutation',7,9
 H.Advance(.05)
 W.guard(timing.catalogPhase==nil and timing.catalogKind==nil and timing.catalogPumps==0 and timing.catalogWork==0,
  'one idle update replaces an older observation: '..tostring(timing.catalogKind)..' '..tostring(timing.catalogPumps))

 -- Original section 2, lines 72-88.
 local donor
 donor=C.Get('synthetic-startup-7')
 W.setup(donor~=nil,'fixture: a stored build to copy')
 local record=H.Clone(donor);record.id='received-idle-1';record.title='Received idle';record.author='Remote-Realm'
 local before=C.Count()
 local ok,why,ticket=C.Put(record)
 W.setup(ok==nil and why=='ROOT_MUTATION_PENDING' and type(ticket)=='table','the write starts a catalog mutation: '..tostring(why))
 for k in pairs(calls) do calls[k]=0 end
 local frames=0
 while ticket.state=='pending' and frames<4000 do H.Advance(.05);frames=frames+1 end
 W.setup(ticket.state=='committed','the write commits: '..tostring(ticket.state)..' after '..frames..' frames')
 W.guard(C.Count()==before+1 and C.Get('received-idle-1')~=nil,'the build is stored: '..C.Count())
 W.guard(calls.pump>0,'pending frames pump admission slices: '..calls.pump)
 emit('ticket1',append(append({{'state',ticket.state},{'reason',ticket.reason},{'frames',frames},
  {'pendingPumps',calls.pump},{'now',H.now}},TimingFields('',TimingSnapshot())),OwnerFields()))
 Frames(20)
 W.guard(calls.pump==0 and calls.root==0,'after the commit the frames are idle again: '..calls.pump..' '..calls.root)
 W.guard(Nexus.StartupStatus().syncGateCatalogReady==true and timing.catalogKind==nil,'idle again: ready, no catalog work shown')

 -- Original section 3, lines 94-100 (the Store coordinator is read through
 -- the raw slice's own upvalue; reading its fields mutates nothing).
 local storeIndex,rawStore
 for i=1,255 do local n,v=debug.getupvalue(runUpdate,i);if not n then break end
  if n=='PumpStoreMutationSlice' then storeIndex,rawStore=i,v end end
 W.setup(storeIndex~=nil,'the lifecycle store slice is found')
 local coord=rawStore and upvalue(rawStore,'bootstrapCoordinator')
 emit('beforePut',append(append(append(append({{'now',H.now},{'rebindRequired',C.RebindRequired()},
  {'preparationPumps',C.PreparationPumpCount()}},PrepFields('prep.',Prep(raw.ManualPreparationStatus))),
  CoordinatorFields('store.',coord)),OwnerFields()),DebugFields('',DebugSubset(C))))
 local second=H.Clone(donor);second.id='received-idle-2';second.title='Received idle 2';second.author='Remote-Realm'
 local ok2,why2,ticket2=C.Put(second)
 W.setup(ok2==nil and why2=='ROOT_MUTATION_PENDING','fixture: a second write is pending: '..tostring(why2))
 local atPut=Identities()
 local debugAtPut=DebugSubset(C)
 local agreesAtPut,bindingAtPut,bindingReasonAtPut=C.SourceBinding()
 emit('atPut',append(append({{'ok2',ok2},{'why2',why2},{'ticket2',type(ticket2)},
  {'ticket2State',type(ticket2)=='table' and ticket2.state or nil},
  {'ticket2Pumps',type(ticket2)=='table' and ticket2.pumps or nil},{'boundIsNexusDB',C.BoundDatabase()==NexusDB},
  {'sourceAgrees',agreesAtPut},{'bindingGeneration',bindingAtPut},{'bindingReason',bindingReasonAtPut},
  {'rebindRequired',C.RebindRequired()},{'preparationPumps',C.PreparationPumpCount()}},
  PrepFields('prep.',Prep(raw.ManualPreparationStatus))),DebugFields('',debugAtPut)))

 -- Original lines 101-109, the same clock replacement and wrapper. The clock
 -- returns exactly realClock()+offset and also records the value; the
 -- wrapper performs the same rawStore call, the same loop and the same offset,
 -- and records what it saw. Nothing here is caught or retried.
 local realClock,offset=debugprofilestop,0
 W.setup(type(realClock)=='function','fixture: a profiler clock')
 local clockPhase='before'
 local clockReads={before={n=0},wrapper={n=0},after={n=0}}
 debugprofilestop=function()
  local value=realClock()+offset
  local list=clockReads[clockPhase]
  list.n=list.n+1
  if #list<16 then list[#list+1]=value end
  return value
 end
 local trace={entered=0,exited=0,storeReturned=0,iterations=0,counts={},first={},last={},transitions={},dropped=0}
 debug.setupvalue(runUpdate,storeIndex,function(...)
  trace.entered=trace.entered+1;clockPhase='wrapper'
  local t0=wallClock()
  trace.stateAtEntry,trace.reasonAtEntry=ticket2.state,ticket2.reason
  trace.storeBefore=CoordinatorFields('storeBefore.',coord)
  trace.pumpsAtEntry=C.PreparationPumpCount()
  trace.prepAtEntry=Prep(raw.ManualPreparationStatus)
  observerMs=observerMs+(wallClock()-t0)
  rawStore(...)
  trace.storeReturned=trace.storeReturned+1
  t0=wallClock()
  trace.storeAfter=CoordinatorFields('storeAfter.',coord)
  trace.identityAfterStore=Identities()
  trace.stateAfterStore,trace.reasonAfterStore=ticket2.state,ticket2.reason
  observerMs=observerMs+(wallClock()-t0)
  local lastPhase=trace.prepAtEntry.phase
  local guard=0
  while ticket2.state=='pending' and guard<100000 do
   local outcome,progressed=raw.PumpRootAdmission();guard=guard+1
   local t1=wallClock()
   local state=type(outcome)=='table' and outcome.state or type(outcome)
   trace.counts[state]=(trace.counts[state] or 0)+1
   local entry=tostring(state)..'/'..tostring(type(outcome)=='table' and outcome.reason or nil)
    ..'/p'..tostring(type(outcome)=='table' and outcome.pumps or nil)..'/'..tostring(progressed)
   if #trace.first<3 then trace.first[#trace.first+1]=entry end
   trace.last[#trace.last+1]=entry;if #trace.last>3 then table.remove(trace.last,1) end
   local s=Prep(raw.ManualPreparationStatus)
   if s.phase~=lastPhase then
    lastPhase=s.phase
    if #trace.transitions<64 then
     trace.transitions[#trace.transitions+1]=table.concat({guard,tostring(s.phase),tostring(s.kind),tostring(s.pumps),
      tostring(s.work),tostring(s.witnessRoot),tostring(s.witnessDepth),tostring(s.relevant),tostring(s.reason),
      tostring(s.ownerAgrees)},':')
    else trace.dropped=trace.dropped+1 end
   end
   observerMs=observerMs+(wallClock()-t1)
  end
  trace.iterations=guard
  offset=offset+5
  trace.pumpsAtExit=C.PreparationPumpCount()
  trace.exited=trace.exited+1
  clockPhase='after'
 end)
 -- C1: a delegating wrapper on the event frame's OnUpdate for this one advance.
 local onUpdate=frame.scripts.OnUpdate
 local dispatch={count=0}
 local initializedBefore=lifecycle.IsInitialized()
 local visibleBefore=frame:IsVisible()
 frame:SetScript('OnUpdate',function(f,elapsed)
  dispatch.count=dispatch.count+1;dispatch.visible=f:IsVisible()
  return onUpdate(f,elapsed)
 end)
 local pre={now=H.now,real=wallClock(),pumps=C.PreparationPumpCount(),wrappedPumps=calls.pump,
  status=calls.status,timing=TimingSnapshot(),perf=Perf(),debug=DebugSubset(C)}
 -- Original line 110. An error leaves the frame exactly as it would in the
 -- original; it is reported here and then raised again unchanged.
 local advanced,advanceError=pcall(H.Advance,.05)
 local realAfter=wallClock()
 frame:SetScript('OnUpdate',onUpdate)
 -- Original lines 111-112.
 debug.setupvalue(runUpdate,storeIndex,rawStore)
 debugprofilestop=realClock

 local class
 if dispatch.count==0 then class=visibleBefore and 'NO_DISPATCH' or 'NO_DISPATCH_FRAME_NOT_VISIBLE'
 elseif not initializedBefore then class='UNINITIALIZED_EARLY_RETURN'
 elseif trace.entered==0 then class='WRAPPER_NOT_CALLED'
 elseif trace.iterations==0 then class='NO_LOOP_TICKET_'..tostring(trace.stateAtEntry)
 else class='LOOP_REACHED_PUMP' end
 emit('C1',{{'class',class},{'advanced',advanced},{'advanceError',advanced and nil or tostring(advanceError)},
  {'dispatches',dispatch.count},{'visibleAtDispatch',dispatch.visible},{'visibleBefore',visibleBefore},
  {'initializedBefore',initializedBefore},{'wrapperEntered',trace.entered},{'rawStoreReturned',trace.storeReturned},
  {'wrapperExited',trace.exited},{'loopIterations',trace.iterations}})
 -- Read at once after the frame, before anything else can publish.
 local bundleIsTicketBundle=ticket2.bundle~=nil and ticket2.bundle==rawget(NexusDB,'authorityBundle')
 local debugAfterFrame=DebugSubset(C)
 local counts={}
 for state,n in pairs(trace.counts) do counts[#counts+1]=state..'='..n end
 table.sort(counts)
 local wrappedPumps=calls.pump-pre.wrappedPumps
 emit('C2',append({{'ticket2State',ticket2.state},{'ticket2Committed',ticket2.committed},{'ticket2Reason',ticket2.reason},
  {'ticket2DatabaseIsNexusDB',ticket2.database==NexusDB},{'ticket2BundleIsLiveBundle',bundleIsTicketBundle},
  {'ticket2Detail',ticket2.detail},{'ticket2Pumps',ticket2.pumps},{'stateAtEntry',trace.stateAtEntry},
  {'reasonAtEntry',trace.reasonAtEntry},{'stateAfterStore',trace.stateAfterStore},{'reasonAfterStore',trace.reasonAfterStore},
  {'outcomes',table.concat(counts,',')},{'firstOutcomes',table.concat(trace.first,' ')},
  {'lastOutcomes',table.concat(trace.last,' ')},{'phaseTransitions',table.concat(trace.transitions,' ')},
  {'transitionsDropped',trace.dropped},{'otherCallerPumpsInFrame',wrappedPumps},
  {'batchStatusReadsInFrame',calls.status-pre.status}},PrepFields('entry.',trace.prepAtEntry or {})))
 local agrees,binding,bindingReason=C.SourceBinding()
 emit('C3',append(append(append(append({{'rebindRequired',C.RebindRequired()},{'boundIsNexusDB',C.BoundDatabase()==NexusDB},
  {'sourceAgrees',agrees},{'bindingGeneration',binding},{'bindingAtPut',bindingAtPut},{'bindingReason',bindingReason},
  {'initialized',lifecycle.IsInitialized()}},trace.storeBefore or {{'storeBefore.observed',false}}),
  trace.storeAfter or {{'storeAfter.observed',false}}),
  trace.identityAfterStore and IdentityFields('afterStore.',trace.identityAfterStore,atPut)
   or {{'afterStore.observed',false}}),IdentityFields('afterFrame.',Identities(),atPut)))
 local function Reads(list,base)
  local out={}
  for i,v in ipairs(list) do out[i]=fmt(v-base) end
  return table.concat(out,',')
 end
 local base=clockReads.before[1] or 0
 local postTiming=TimingSnapshot()
 local postPerf=Perf()
 local perfFields={}
 for _,name in ipairs(PERF) do
  perfFields[#perfFields+1]={name..'.runs',(tonumber(postPerf[name].count) or 0)-(tonumber(pre.perf[name].count) or 0)}
  perfFields[#perfFields+1]={name..'.lastMs',postPerf[name].last}
 end
 local gate=Nexus.StartupStatus()
 emit('C4',append({{'syntheticAdvanceS',H.now-pre.now},{'realElapsedMs',realAfter-pre.real},
  {'observerMsInFrame',observerMs},{'clockReadsBefore',clockReads.before.n},{'clockReadsWrapper',clockReads.wrapper.n},
  {'clockReadsAfter',clockReads.after.n},{'readsBeforeMs',Reads(clockReads.before,base)},
  {'readsWrapperMs',Reads(clockReads.wrapper,base)},{'readsAfterMs',Reads(clockReads.after,base)},
  {'preparationPumpsAtFrameStart',pre.pumps},{'pumpsAtWrapperEntry',trace.pumpsAtEntry},
  {'pumpsAtWrapperExit',trace.pumpsAtExit},
  {'priorSlices',trace.pumpsAtExit and (trace.pumpsAtExit-pre.pumps) or nil},
  {'driveSlicesDelta',postTiming.driveSlices-pre.timing.driveSlices},
  {'driveOvershootsDelta',postTiming.driveOvershoots-pre.timing.driveOvershoots},
  {'driveMaxBatchMs',postTiming.driveMaxBatchMs},{'driveMaxBatchMsBefore',pre.timing.driveMaxBatchMs},
  {'driveFallbackDelta',postTiming.driveFallbackUpdates-pre.timing.driveFallbackUpdates},
  {'syncGate',gate.syncGate},{'syncGateCatalogReady',gate.syncGateCatalogReady},
  {'syncGateHashesReady',gate.syncGateHashesReady}},perfFields))
 emit('C2debug',DebugFields('delta.',debugAfterFrame,pre.debug))
 if not advanced then error(advanceError,0) end

 -- Original lines 113-117.
 W.setup(ticket2.state=='committed','fixture: the write committed inside the preparation window',
  tostring(ticket2.state)..'/'..tostring(ticket2.reason)..' class='..class)
 W.guard(Nexus.StartupStatus().syncGateCatalogReady==false,
  'over the allowance: not reported ready in this update (as on test.9053): '..tostring(Nexus.StartupStatus().syncGate))
 H.Advance(.05)
 W.guard(Nexus.StartupStatus().syncGateCatalogReady==true,'the next update reports the catalog ready')

 -- C5 effects, after the original sequence. Evaluated only for a committed
 -- ticket2; otherwise what the next frames do is printed, not asserted.
 if ticket2.state=='committed' then
  W.guard(C.Count()==before+2 and C.Get('received-idle-2')~=nil,'the second build is served: '..C.Count())
  W.guard(ticket2.database==NexusDB and bundleIsTicketBundle,
   'right after its frame, the commit was the live durable bundle')
  W.guard((tonumber(debugAfterFrame.bundleWrites) or 0)>(tonumber(debugAtPut.bundleWrites) or 0)
   and (tonumber(debugAfterFrame.servingSwaps) or 0)>(tonumber(debugAtPut.servingSwaps) or 0),
   'the commit wrote the durable bundle and swapped the serving root in its frame')
  Frames(20)
  W.guard(calls.pump==0 and calls.root==0,'after the second commit the frames are idle again: '..calls.pump..' '..calls.root)
  emit('C5',{{'evaluated',true},{'idlePumps',calls.pump},{'idleRootReads',calls.root},{'count',C.Count()}})
 else
  Frames(20)
  emit('C5',{{'evaluated',false},{'ticket2State',ticket2.state},{'ticket2Reason',ticket2.reason},
   {'pumpsIn20Frames',calls.pump},{'rootReadsIn20Frames',calls.root},
   {'syncGate',Nexus.StartupStatus().syncGate}})
 end

 -- Original line 119.
 for name in pairs(wrapped) do C[name]=raw[name] end
end)

W.finish('(witness: observations above; a PASS does not explain the historical first red; synthetic services, no native claim)')
