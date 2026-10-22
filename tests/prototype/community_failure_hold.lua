-- Real TOC, Community facade/controller/projection factory and registered frame.
-- Faults touch only public dependencies or synthetic host methods. No renderer,
-- List or PumpBuilds replacement; no native timing or global error-history claim.
-- Checker classifications use staged baselines: original failure/receive/import
-- regressions against 1f993d7; explicit-query latency and handled-message cases
-- against 1be520d; failed explicit-request timing and thrown-message cases against
-- 8e03747. Later SETUPs may rely on earlier retained-error repairs. Existing
-- predicates stay in the file to guard those accepted stages on every replay.
-- The advancing-clock explicit exception uses 6dd5ceae as its baseline. It
-- characterizes synthetic timing robustness, not native GetTime clock caching.
-- Show/direct-refresh, cached-render retry, replacement liveness and frame-clock
-- regressions use 688f6b9. Hidden dormancy and safety-refresh roles guard that pin.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('community_failure_hold')
local function Boot(receiving,empty)
 local H=F.Boot(F.Database(),function(h)
  h.perks.serverBuildSlots=empty and {} or {[1]={name='Failure hold slot',verified=true,
   echoes={{spellId=200001,quality=1,stacks=1,locked=false}}}}
  h.perks.serverActiveSlot=1
 end)
 C.setup(Nexus.StartupStatus().state=='ready','real TOC startup ready')
 Nexus.Sync.IsReceiving=function() return receiving.value end
 return H,Nexus.CommunityBuilds
end
local function Step(H,count,beforeFrame)
 local escaped=0
 for _=1,count do
  if beforeFrame then beforeFrame() end
  if not pcall(H.Advance,.01,.01) then escaped=escaped+1 end
 end
 return escaped
end
local function SafetyReads()
 local count=0
 local read=Nexus.ViewProjections.BuildsCurrent
 Nexus.ViewProjections.BuildsCurrent=function(...)
  count=count+1;return read(...)
 end
 return function() return count end
end
local function Settle(H,CB,limit)
 for i=1,limit or 2000 do
  if CB.DiagnosticSnapshot().projectionCurrent
   and not CB.VirtualStats().savedImport.pending then return i-1 end
  Step(H,1)
 end
 return nil
end

C.scenario('failed-job-diagnostic',function()
 local H,CB=Boot({value=false},true)
 local attempts=0
 Nexus.DpsCapture.CommunityEligibilityCursorNext=function()
  attempts=attempts+1;return false,'Synthetic retained eligibility failure'
 end
 CB.Show()
 C.setup(CB.DiagnosticSnapshot().projectionPending,'real factory requested a production job')
 local escaped=Step(H,100)
 local d,stats=CB.DiagnosticSnapshot(),CB.VirtualStats()
 print('OBSERVED failed-job-diagnostic','attempts='..attempts,'escaped='..escaped,
  'reason='..d.blockedReason,'pending='..tostring(d.projectionPending))
 C.expect(d.blockedReason=='projection-error',
  'failed production job remains an error instead of replacement pending',d.blockedReason)
 C.guard(d.projectionDirty and not d.projectionCurrent,
  'failed view stays dirty and not current while pending status stays truthful')
 C.guard(stats.lastDataError and stats.lastDataError:find('Synthetic retained eligibility failure',1,true),
  'failure message remains in the public view stats')
 C.guard(attempts>0 and attempts<=3 and escaped==0,
  'real reader was reached and retry backoff contains returned failure',attempts)
 C.guard(Nexus.ViewProjections.Stats().builds.failures>0,'production job records the dependency failure')
 C.guard(#H.actions==0 and #H.sent==0,'fault observation sends no game or network action')
end)

C.scenario('dirty-notifications-hold',function()
 local H,CB=Boot({value=true})
 CB.Show();NexusCommunityBuildsFrame._myBuildsBtn:Click()
 C.setup(CB.DiagnosticSnapshot().publishedPage==0 and CB.VirtualStats().savedImport.pending,
  'cold Mine view defers its saved import during receive')
 local attempts=0
 NexusCommunityBuildsFrame._classDropBtn.SetText=function()
  attempts=attempts+1;error('Synthetic dirty-event render failure')
 end
 local reads=SafetyReads()
 local before=CB.VirtualStats().savedImport.syncDeferrals
 -- Public dirty notifications describe the same current view. They are not a
 -- new filter/search/scope request and cannot erase an active failure deadline.
 local escaped=Step(H,1000,function() CB.MarkDataDirty() end)
 local deferrals=CB.VirtualStats().savedImport.syncDeferrals-before
 print('OBSERVED dirty-notifications-hold','frames=1000 attempts='..attempts,
  'escaped='..escaped,'safety='..reads(),'import-checks='..deferrals)
 C.expect(attempts>0 and attempts<=6,
  'repeated same-view dirty notifications retain failure backoff',attempts)
 C.expect(CB.DiagnosticSnapshot().blockedReason=='projection-error',
  'an independent saved import does not mask a retained render failure',CB.DiagnosticSnapshot().blockedReason)
 C.guard(escaped==0,'persistent host exception stays inside the frame',escaped)
 C.guard(reads()>=1,'eight-second safety observer survives the held failure',reads())
 C.guard(deferrals==1000 and CB.VirtualStats().savedImport.pending,
  'healthy deferred import remains independent on every frame',deferrals)
 C.guard(#H.actions==0 and #H.sent==0,'dirty notifications send no game or network action')
end)

C.scenario('receive-end-churn',function()
 local receiving={value=false}
 local H,CB=Boot(receiving,true)
 CB.Show()
 C.setup(Settle(H,CB)~=nil,'warm publication and saved import have settled')
 local attempts=0
 NexusCommunityBuildsFrame._classDropBtn.SetText=function()
  attempts=attempts+1;error('Synthetic receive-end render failure')
 end
 local before=CB.VirtualStats().deferredRefreshes
 local frame=0
 local escaped=Step(H,1000,function()
  frame=frame+1
  receiving.value=math.floor((frame-1)/25)%2==0
  CB.MarkDataDirty()
 end)
 local d,stats=CB.DiagnosticSnapshot(),CB.VirtualStats()
 print('OBSERVED receive-end-churn','frames=1000 attempts='..attempts,
  'escaped='..escaped,'receive-end-refreshes='..(stats.deferredRefreshes-before),
  'reason='..d.blockedReason)
 C.setup(stats.deferredRefreshes>before,'real status ticker observed dirty receive-end transitions')
 C.expect(attempts>0 and attempts<=6,
  'receive-end transitions cannot erase an active failure hold',attempts)
 C.expect(d.blockedReason=='projection-error' and d.projectionDirty and not d.projectionCurrent,
  'receive-end churn retains visible failure and stale publication',d.blockedReason)
 C.expect(stats.lastDataError and stats.lastDataError:find('Synthetic receive-end render failure',1,true),
  'receive-end failure message remains available in public stats')
 C.guard(escaped==0,'receive-end refresh exception stays inside the frame',escaped)
 C.guard(not stats.savedImport.pending,'receive-end test is independent of import completion')
 C.guard(#H.actions==0 and #H.sent==0,'receive-end observation sends no game or network action')
end)

C.scenario('dependency-recovery',function()
 local H,CB=Boot({value=false},true)
 local read=Nexus.DpsCapture.CommunityEligibilityCursorNext
 Nexus.DpsCapture.CommunityEligibilityCursorNext=function()
  return false,'Synthetic recoverable eligibility failure'
 end
 CB.Show();Step(H,100)
 C.setup(CB.VirtualStats().dataFailures>0,
  'production projection reached the recoverable dependency failure')
 local failures=CB.VirtualStats().dataFailures
 Nexus.DpsCapture.CommunityEligibilityCursorNext=read
 local settled=Settle(H,CB)
 local d,stats=CB.DiagnosticSnapshot(),CB.VirtualStats()
 print('OBSERVED dependency-recovery','settled-frames='..tostring(settled),
  'reason='..d.blockedReason,'failures='..stats.dataFailures)
 C.guard(settled~=nil and d.projectionCurrent and not d.projectionDirty
  and not d.projectionPending and d.blockedReason=='none',
  'restored dependency publishes a current view and clears failure state',d.blockedReason)
 C.guard(stats.lastDataError==nil,'successful recovery clears the retained failure message')
 C.guard(stats.dataFailures==failures,'healthy recovery adds no failure',stats.dataFailures)
 C.guard(#H.actions==0 and #H.sent==0,'dependency recovery sends no game or network action')
end)

C.scenario('explicit-filter-recovery',function()
 local H,CB=Boot({value=false},true)
 local read=Nexus.DpsCapture.CommunityEligibilityCursorNext
 Nexus.DpsCapture.CommunityEligibilityCursorNext=function()
  return false,'Synthetic old-filter eligibility failure'
 end
 CB.Show();Step(H,100)
 C.setup(CB.VirtualStats().dataFailures>0,
  'old filter context has a retained projection failure')
 local before=CB.DiagnosticSnapshot().filterCurrentClassOnly
 Nexus.DpsCapture.CommunityEligibilityCursorNext=read
 NexusCommunityBuildsFrame._classDropBtn:Click()
 local changed=CB.DiagnosticSnapshot()
 C.guard(changed.filterCurrentClassOnly~=before,'real filter control changes the requested context')
 C.guard(not changed.projectionCurrent and changed.projectionDirty,
  'new filter does not claim the old publication is current while work is pending')
 local settled=Settle(H,CB)
 local d=CB.DiagnosticSnapshot()
 print('OBSERVED explicit-filter-recovery','settled-frames='..tostring(settled),
  'reason='..d.blockedReason,'class-only='..tostring(d.filterCurrentClassOnly))
 C.guard(settled~=nil and d.filterCurrentClassOnly~=before
  and d.projectionCurrent and not d.projectionDirty and d.blockedReason=='none',
  'successful new filter publication truthfully replaces the failed context',d.blockedReason)
 C.guard(CB.VirtualStats().lastDataError==nil,'new current publication clears the old failure message')
 C.guard(#H.actions==0 and #H.sent==0,'filter recovery sends no game or network action')
end)

C.scenario('healthy-import-and-cadence',function()
 local receiving={value=true}
 local H,CB=Boot(receiving)
 CB.Show();NexusCommunityBuildsFrame._myBuildsBtn:Click()
 local frame=NexusCommunityBuildsFrame
 local before=CB.VirtualStats().savedImport
 C.setup(before.pending and before.pumps==0,'cold Mine import is deferred before any work')
 local writes=0
 local setText=frame._classDropBtn.SetText
 frame._classDropBtn.SetText=function(self,text)
  writes=writes+1;return setText(self,text)
 end
 local pumpBefore=Nexus.ViewProjections.WorkStats().communityPumps
 local escaped=Step(H,100)
 local deferred=CB.VirtualStats().savedImport
 local projectionPumps=Nexus.ViewProjections.WorkStats().communityPumps-pumpBefore
 print('OBSERVED healthy-import-and-cadence','cold-refresh-writes='..writes,
  'projection-pumps='..projectionPumps,'receive-checks='..(deferred.syncDeferrals-before.syncDeferrals))
 C.guard(writes>0 and writes<=10 and projectionPumps<=10,
  'cold receive refresh and projection work respect the 100ms cadence',writes)
 C.guard(escaped==0 and deferred.pending and deferred.syncDeferrals-before.syncDeferrals==100,
  'healthy saved import remains independently deferred on every frame')
 receiving.value=false
 Step(H,1)
 local first=CB.VirtualStats().savedImport
 C.guard(first.pumps==deferred.pumps+1 and first.workUnits>deferred.workUnits,
  'saved import advances on the first 10ms frame after receive',first.pumps)
 local settled=Settle(H,CB)
 local final=CB.VirtualStats().savedImport
 local mirrors={}
 for _,row in pairs(CB.Builds()) do
  if row.importedSavedBuild and row.serverSlot==1 then mirrors[#mirrors+1]=row end
 end
 print('OBSERVED healthy-import-completion','pumps='..final.pumps,
  'puts='..final.catalogPuts,'put-calls='..final.catalogPutCalls,
  'writes='..final.writes,'completions='..final.completions,'mirrors='..#mirrors)
 C.guard(settled~=nil and not final.pending and final.completions==1,
  'actual saved import and projection settle once')
 C.guard(final.catalogPuts==1 and final.catalogPutCalls==1 and final.writes==1,
  'per-frame pumping never resubmits a pending catalog write')
 C.guard(#mirrors==1 and CB.IsOwnBuild(mirrors[1].id) and mirrors[1].ownerVerified,
  'one owned verified saved mirror is served')
 local record=mirrors[1] and Nexus.BuildCatalog.Get(mirrors[1].id)
 C.guard(record and #record.echoes==1 and record.echoes[1].spellId==200001,
  'saved mirror retains its synthetic Echo')
 C.guard(final.maxWorkPerPump<=25,'existing import work budget is preserved',final.maxWorkPerPump)
 C.guard(#H.actions==0 and #H.sent==0,'healthy import sends no game or network action')
end)

C.scenario('receive-end-first-frame-import',function()
 local receiving={value=true}
 local H,CB=Boot(receiving)
 CB.Show();NexusCommunityBuildsFrame._myBuildsBtn:Click()
 -- Align a real receive-end observation with the first nonreceiving frame.
 H.Advance(.26,.26)
 local before=CB.VirtualStats().savedImport
 C.setup(before.pending and before.pumps==0,'saved import waits during the observed receive window')
 receiving.value=false
 H.Advance(.26,.26)
 local first=CB.VirtualStats().savedImport
 print('OBSERVED receive-end-first-frame-import','before='..before.pumps,'after='..first.pumps)
 C.expect(first.pumps==before.pumps+1 and first.workUnits>before.workUnits,
  'the receive-end frame advances its saved import before ordinary refresh can return',first.pumps)
 Step(H,1000)
 local final=CB.VirtualStats().savedImport
 C.guard(not final.pending and final.completions==1 and final.catalogPutCalls==1 and final.writes==1,
  'the same resumed import commits exactly once')
 C.guard(#H.actions==0 and #H.sent==0,'receive-end import sends no game or network action')
end)

C.scenario('explicit-filter-work-during-hold',function()
 local H,CB=Boot({value=false},true)
 local read=Nexus.DpsCapture.CommunityEligibilityCursorNext
 local message='Synthetic previous-query failure'
 Nexus.DpsCapture.CommunityEligibilityCursorNext=function() return false,message end
 CB.Show()
 for _=1,100 do
  if CB.VirtualStats().dataFailures>0 then break end
  Step(H,1)
 end
 local failed=CB.VirtualStats()
 C.setup(failed.dataFailures==1 and failed.lastDataError
  and failed.lastDataError:find(message,1,true)
  and CB.DiagnosticSnapshot().blockedReason=='projection-error',
  'a real failed projection establishes the first active failure hold')
 local heldPumps=Nexus.ViewProjections.WorkStats().communityPumps
 Step(H,10,function() CB.MarkDataDirty() end)
 C.guard(Nexus.ViewProjections.WorkStats().communityPumps==heldPumps
  and CB.VirtualStats().dataFailures==failed.dataFailures,
  'ordinary same-query dirty notifications keep the active hold')
 local previousClass=CB.DiagnosticSnapshot().filterCurrentClassOnly
 Nexus.DpsCapture.CommunityEligibilityCursorNext=read
 NexusCommunityBuildsFrame._classDropBtn:Click()
 local requested=CB.DiagnosticSnapshot()
 C.setup(requested.filterCurrentClassOnly~=previousClass and requested.projectionPending,
  'real class click requests a healthy distinct pending projection')
 C.guard(requested.blockedReason=='projection-error' and requested.projectionDirty
  and not requested.projectionCurrent and CB.VirtualStats().lastDataError==failed.lastDataError,
  'new pending work retains the prior error evidence until publication')
 local before=Nexus.ViewProjections.WorkStats().communityPumps
 local firstWork,pendingEvidence,escaped=nil,true,0
 for i=1,20 do
  escaped=escaped+Step(H,1)
  local d=CB.DiagnosticSnapshot()
  if not d.projectionCurrent then
   pendingEvidence=pendingEvidence and d.blockedReason=='projection-error'
    and CB.VirtualStats().lastDataError==failed.lastDataError
  end
  if not firstWork and Nexus.ViewProjections.WorkStats().communityPumps>before then firstWork=i end
 end
 local progress=Nexus.ViewProjections.WorkStats().communityPumps-before
 print('OBSERVED explicit-filter-work-during-hold','frames=20 first-work='..tostring(firstWork),
  'positive-pumps='..progress,'reason='..CB.DiagnosticSnapshot().blockedReason)
 C.expect(firstWork~=nil and progress>0,
  'explicit healthy filter query advances projection work within 200ms of its request',progress)
 C.guard(pendingEvidence,'every observed pending frame retains failure evidence')
 C.guard(escaped==0 and CB.VirtualStats().dataFailures==failed.dataFailures,
  'healthy new-query work causes no exception or additional failure',escaped)
 C.guard(#H.actions==0 and #H.sent==0,'explicit query sends no game or network action')
end)

C.scenario('pending-observations-do-not-extend-hold',function()
 local H,CB=Boot({value=false},true)
 local read=Nexus.DpsCapture.CommunityEligibilityCursorNext
 Nexus.DpsCapture.CommunityEligibilityCursorNext=function()
  return false,'Synthetic fixed-deadline failure'
 end
 CB.Show()
 for _=1,100 do
  if CB.VirtualStats().dataFailures>0 then break end
  Step(H,1)
 end
 C.setup(CB.VirtualStats().dataFailures==1 and CB.DiagnosticSnapshot().projectionPending,
  'one production failure has left replacement work pending')
 Nexus.DpsCapture.CommunityEligibilityCursorNext=read
 local before=Nexus.ViewProjections.WorkStats().communityPumps
 local firstWork
 -- Re-reading the same pending query neither releases nor renews its 500ms
 -- first-failure deadline. The next 100ms work tick must still become due.
 for i=1,70 do
  CB.Refresh();Step(H,1)
  if not firstWork and Nexus.ViewProjections.WorkStats().communityPumps>before then firstWork=i end
 end
 print('OBSERVED pending-observations-do-not-extend-hold','frames=70 first-work='..tostring(firstWork),
  'failures='..CB.VirtualStats().dataFailures)
 C.guard(firstWork and firstWork>=50 and firstWork<=70,
  'same-query pending observations keep the original deadline instead of sliding it',firstWork)
 C.guard(CB.VirtualStats().dataFailures==1,'pending observations do not record new failures')
 C.guard(#H.actions==0 and #H.sent==0,'pending observation sends no game or network action')
end)

C.scenario('latest-handled-failure-message',function()
 local H,CB=Boot({value=false},true)
 local read=Nexus.DpsCapture.CommunityEligibilityCursorNext
 Nexus.DpsCapture.CommunityEligibilityCursorNext=function()
  return false,'Synthetic older pump failure'
 end
 CB.Show();Step(H,100)
 local before=CB.VirtualStats()
 C.setup(before.dataFailures>0 and before.lastDataError=='Synthetic older pump failure',
  'an older production pump failure has a retained message')
 Nexus.DpsCapture.CommunityEligibilityCursorNext=read
 local begin=Nexus.DpsCapture.BeginCommunityEligibilityCursor
 local refusals=0
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=function()
  refusals=refusals+1;return nil
 end
 CB.MarkDataDirty();NexusCommunityBuildsFrame._classDropBtn:Click()
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=begin
 local after,d=CB.VirtualStats(),CB.DiagnosticSnapshot()
 C.setup(refusals>0 and after.dataFailures>before.dataFailures,
  'a new explicit query reaches the handled production factory refusal')
 print('OBSERVED latest-handled-failure-message','refusals='..refusals,
  'message='..tostring(after.lastDataError))
 C.expect(after.lastDataError=='DPS eligibility cursor unavailable',
  'a newer handled failure replaces the older message',after.lastDataError)
 C.guard(d.blockedReason=='projection-error' and d.projectionDirty and not d.projectionCurrent,
  'the newer handled failure stays visible and not current')
 C.guard(#H.actions==0 and #H.sent==0,'handled failure sends no game or network action')
end)

C.scenario('replacement-handled-failure-message',function()
 local H,CB=Boot({value=false},true)
 local begin=Nexus.DpsCapture.BeginCommunityEligibilityCursor
 local refuse,refusals=false,0
 Nexus.DpsCapture.CommunityEligibilityCursorNext=function()
  refuse=true;return false,'Synthetic failed job before replacement'
 end
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=function(...)
  if refuse then refusals=refusals+1;return nil end
  return begin(...)
 end
 CB.Show()
 for _=1,200 do
  if refusals>0 then break end
  Step(H,1)
 end
 local stats,d=CB.VirtualStats(),CB.DiagnosticSnapshot()
 C.setup(refusals>0 and stats.dataFailures==1,
  'a failed production job reaches a replacement factory refusal within its first hold')
 print('OBSERVED replacement-handled-failure-message','refusals='..refusals,
  'message='..tostring(stats.lastDataError))
 C.expect(stats.lastDataError=='DPS eligibility cursor unavailable',
  'requesting a replacement retains its latest handled failure message',stats.lastDataError)
 C.guard(d.blockedReason=='projection-error' and d.projectionDirty and not d.projectionCurrent,
  'a refused replacement does not claim publication or clear failure')
 C.guard(#H.actions==0 and #H.sent==0,'replacement refusal sends no game or network action')
end)

C.scenario('explicit-persistent-handled-failure-hold',function()
 local H,CB=Boot({value=false},true)
 CB.Show()
 C.setup(Settle(H,CB)~=nil,'healthy view and import settle before an explicit refusal')
 local begin=Nexus.DpsCapture.BeginCommunityEligibilityCursor
 local refusals=0
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=function()
  refusals=refusals+1;return nil
 end
 NexusCommunityBuildsFrame._classDropBtn:Click()
 local afterClick=refusals
 C.setup(afterClick==1 and CB.VirtualStats().dataFailures>0,
  'real class request reaches a handled production factory refusal')
 local escaped=Step(H,40)
 local afterQuiet=refusals
 print('OBSERVED explicit-persistent-handled-failure-hold','after-click='..afterClick,
  'after-400ms='..afterQuiet)
 C.expect(afterQuiet==afterClick,
  'a failed explicit query installs its hold before any 400ms background retry',afterQuiet)
 Step(H,100)
 C.guard(refusals>afterQuiet,'persistent failure eventually retries after its deadline',refusals)
 C.guard(escaped==0 and CB.DiagnosticSnapshot().blockedReason=='projection-error'
  and CB.VirtualStats().lastDataError=='DPS eligibility cursor unavailable',
  'persistent refusal is contained and remains visible')
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=begin
 C.guard(Settle(H,CB)~=nil,'restoring the refused factory eventually recovers')
 C.guard(#H.actions==0 and #H.sent==0,'explicit refusal sends no game or network action')
end)

C.scenario('transient-explicit-refusal-fixed-deadline',function()
 local H,CB=Boot({value=false},true)
 CB.Show()
 C.setup(Settle(H,CB)~=nil,'healthy view settles before a transient explicit refusal')
 local begin=Nexus.DpsCapture.BeginCommunityEligibilityCursor
 local refusals=0
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=function()
  refusals=refusals+1;return nil
 end
 NexusCommunityBuildsFrame._classDropBtn:Click()
 C.setup(refusals==1 and CB.VirtualStats().dataFailures==1,
  'one explicit query records its own transient handled failure')
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=begin
 -- This is the same failed query, observed through the non-releasing facade.
 -- A healthy pending observation must not become the deadline's new origin.
 CB.Refresh()
 C.setup(CB.DiagnosticSnapshot().projectionPending,'restored factory provides real healthy replacement work')
 local before=Nexus.ViewProjections.WorkStats().communityPumps
 local firstWork
 for i=1,70 do
  Step(H,1)
  if not firstWork and Nexus.ViewProjections.WorkStats().communityPumps>before then firstWork=i end
 end
 print('OBSERVED transient-explicit-refusal-fixed-deadline','frames=70 first-work='..tostring(firstWork))
 C.expect(firstWork and firstWork>=50 and firstWork<=70,
  'transient refusal holds replacement work to its original failure deadline',firstWork)
 C.guard(CB.VirtualStats().dataFailures==1,'healthy pending replacement adds no failure')
 C.guard(Settle(H,CB)~=nil and CB.VirtualStats().lastDataError==nil,
  'healthy replacement eventually publishes and clears the transient message')
 C.guard(#H.actions==0 and #H.sent==0,'transient refusal sends no game or network action')
end)

C.scenario('explicit-refresh-throw-retained-and-held',function()
 local H,CB=Boot({value=false},true)
 CB.Show()
 C.setup(Settle(H,CB)~=nil,'healthy view settles before a thrown explicit refresh')
 local frame=NexusCommunityBuildsFrame
 local setText=frame._classDropBtn.SetText
 local calls,armed=0,true
 local message='Synthetic one-shot explicit refresh failure'
 frame._classDropBtn.SetText=function(self,text)
  calls=calls+1
  if armed then armed=false;error(message,0) end
  return setText(self,text)
 end
 local ok,err=pcall(function() frame._classDropBtn:Click() end)
 C.setup(calls==1,'actual explicit refresh reaches the one-shot host fault')
 C.guard(not ok and err==message,'explicit refresh rethrows the original error value',err)
 local stats,d=CB.VirtualStats(),CB.DiagnosticSnapshot()
 C.expect(stats.dataFailures==1 and stats.lastDataError==message
  and d.blockedReason=='projection-error' and d.projectionDirty and not d.projectionCurrent,
  'thrown explicit refresh retains its message and failure state before rethrow',stats.lastDataError)
 local pumps=Nexus.ViewProjections.WorkStats().communityPumps
 local escaped=Step(H,40)
 print('OBSERVED explicit-refresh-throw-retained-and-held','calls-after-400ms='..calls,
  'positive-pumps='..(Nexus.ViewProjections.WorkStats().communityPumps-pumps),
  'message='..tostring(stats.lastDataError))
 C.guard(calls==1 and Nexus.ViewProjections.WorkStats().communityPumps==pumps,
  'one-shot thrown explicit refresh installs a hold before returning to the frame',calls)
 C.guard(escaped==0,'subsequent automatic refresh contains no escaped error',escaped)
 local recovered=false
 -- A throw before SortedBuilds can leave the old projectionCurrent flag true.
 -- Require actual new production work as well as a current publication, within
 -- 200 total 10ms frames of the request (40 above, at most 160 below).
 for _=1,160 do
  Step(H,1)
  local current=CB.DiagnosticSnapshot()
  if Nexus.ViewProjections.WorkStats().communityPumps>pumps and current.projectionCurrent
   and not current.projectionPending and not current.projectionDirty then recovered=true;break end
 end
 print('OBSERVED explicit-refresh-throw-recovery','recovered='..tostring(recovered),
  'positive-pumps='..(Nexus.ViewProjections.WorkStats().communityPumps-pumps))
 C.expect(recovered and CB.VirtualStats().lastDataError==nil,
  'the failed explicit request resumes production work and publishes within two seconds')
 C.guard(#H.actions==0 and #H.sent==0,'explicit refresh exception sends no game or network action')
end)

C.scenario('replacement-thrown-failure-message',function()
 local H,CB=Boot({value=false},true)
 local read=Nexus.DpsCapture.CommunityEligibilityCursorNext
 local nextCalls,throws,armed=0,0,false
 local older='Synthetic older pump failure before replacement throw'
 local newer='Synthetic newer replacement refresh throw'
 Nexus.DpsCapture.CommunityEligibilityCursorNext=function()
  nextCalls=nextCalls+1;armed=true;return false,older
 end
 CB.Show()
 local frame=NexusCommunityBuildsFrame
 local setText=frame._classDropBtn.SetText
 frame._classDropBtn.SetText=function(self,text)
  if armed then armed=false;throws=throws+1;error(newer,0) end
  return setText(self,text)
 end
 local escaped=0
 for _=1,200 do
  if throws>0 then break end
  escaped=escaped+Step(H,1)
 end
 local stats,d=CB.VirtualStats(),CB.DiagnosticSnapshot()
 C.setup(nextCalls==1 and throws==1 and stats.dataFailures==1,
  'a real failed production job reaches the one-shot replacement host exception')
 print('OBSERVED replacement-thrown-failure-message','next-calls='..nextCalls,
  'throws='..throws,'message='..tostring(stats.lastDataError))
 C.expect(stats.lastDataError==newer,
  'the newer automatic replacement exception replaces the older pump message',stats.lastDataError)
 C.guard(escaped==0 and d.blockedReason=='projection-error'
  and d.projectionDirty and not d.projectionCurrent,
  'replacement exception remains contained and leaves a failed current request')
 C.guard(stats.dataFailures==1,'replacement exception preserves the original hold failure count')
 C.guard(#H.actions==0 and #H.sent==0,'replacement exception sends no game or network action')
 C.expect(not d.projectionPending,
  'thrown automatic replacement does not claim its cancelled job is pending')
 Nexus.DpsCapture.CommunityEligibilityCursorNext=read
 local pumps=Nexus.ViewProjections.WorkStats().communityPumps
 local recovered=Settle(H,CB,200)
 local final=CB.VirtualStats()
 print('OBSERVED replacement-thrown-failure-recovery','frames='..tostring(recovered),
  'positive-pumps='..(Nexus.ViewProjections.WorkStats().communityPumps-pumps))
 C.expect(recovered~=nil and Nexus.ViewProjections.WorkStats().communityPumps>pumps
  and final.lastDataError==nil and final.dataFailures==1,
  'replacement exception resumes actual work and publishes within two seconds of the hold')
end)

C.scenario('explicit-refresh-throw-clock-advance',function()
 local H,CB=Boot({value=false},true)
 CB.Show()
 if not C.setup(Settle(H,CB)~=nil,
  'healthy view settles before the advancing-clock explicit exception') then return end
 local frame=NexusCommunityBuildsFrame
 local setText=frame._classDropBtn.SetText
 local calls,armed=0,true
 local message='Synthetic clock-advanced explicit refresh failure'
 frame._classDropBtn.SetText=function(self,text)
  calls=calls+1
  if armed then
   armed=false
   -- No recursive frame dispatch. This models a clock that advances during
   -- a synchronous host call; native frame-cached GetTime remains unproven.
   H.now=H.now+.6
   error(message,0)
  end
  return setText(self,text)
 end
 local requestedAt=GetTime()
 local ok,err=pcall(function() frame._classDropBtn:Click() end)
 local caughtAt=GetTime()
 if not C.setup(calls==1 and caughtAt-requestedAt>.59,
  'real class request reaches one host fault after 600ms synthetic clock advance') then return end
 C.guard(not ok and err==message,
  'clock-advanced explicit exception rethrows its unchanged original value',err)
 local failed,d=CB.VirtualStats(),CB.DiagnosticSnapshot()
 C.guard(failed.dataFailures==1 and failed.lastDataError==message
  and d.blockedReason=='projection-error' and d.projectionDirty and not d.projectionCurrent,
  'clock-advanced exception is immediately visible with one failure',failed.lastDataError)
 local pumps=Nexus.ViewProjections.WorkStats().communityPumps
 local escaped=Step(H,40)
 print('OBSERVED explicit-refresh-throw-clock-advance','request-time='..requestedAt,
  'catch-time='..caughtAt,'calls-after-400ms='..calls,
  'positive-pumps='..(Nexus.ViewProjections.WorkStats().communityPumps-pumps))
 C.expect(calls==1 and Nexus.ViewProjections.WorkStats().communityPumps==pumps,
  'clock-advanced explicit failure holds automatic retry for 400ms after it is observed',calls)
 local recovered=false
 for _=1,160 do
  escaped=escaped+Step(H,1)
  local current=CB.DiagnosticSnapshot()
  if Nexus.ViewProjections.WorkStats().communityPumps>pumps and current.projectionCurrent
   and not current.projectionPending and not current.projectionDirty then recovered=true;break end
 end
 local final=CB.VirtualStats()
 print('OBSERVED explicit-refresh-throw-clock-recovery','recovered='..tostring(recovered),
  'elapsed-after-catch='..(GetTime()-caughtAt),
  'positive-pumps='..(Nexus.ViewProjections.WorkStats().communityPumps-pumps))
 C.expect(recovered and final.lastDataError==nil,
  'clock-advanced exception eventually resumes real work and publishes within two seconds')
 C.guard(final.dataFailures==1 and escaped==0,
  'healthy clock-advanced recovery adds no failure or escaped background exception',escaped)
 C.guard(#H.actions==0 and #H.sent==0,'clock-advanced exception sends no game or network action')
end)

C.scenario('show-handled-failure-hidden-hold',function()
 local receiving={value=true}
 local H,CB=Boot(receiving,true)
 -- Finish the independent startup ViewRefresh callback while this window is
 -- hidden, so the measured retries belong to its registered frame pump.
 Step(H,100)
 local begin=Nexus.DpsCapture.BeginCommunityEligibilityCursor
 local refusals=0
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=function()
  refusals=refusals+1;return nil
 end
 CB.Show()
 if not C.setup(refusals==1 and CB.VirtualStats().dataFailures==1
  and CB.VirtualStats().savedImport.pending and CB.VirtualStats().savedImport.pumps==0,
  'Show records one handled failure while an empty saved import is deferred') then return end
 receiving.value=false
 local escaped=Step(H,40)
 local quiet=refusals
 print('OBSERVED show-handled-failure-hold','after-show=1','after-400ms='..quiet,
  'import-pending='..tostring(CB.VirtualStats().savedImport.pending))
 C.expect(quiet==1,'Show failure holds automatic retry including empty import completion',quiet)
 C.guard(not CB.VirtualStats().savedImport.pending,
  'healthy empty saved import completes independently of the view hold')
 local frame=NexusCommunityBuildsFrame
 CB.Hide()
 local hidden=CB.VirtualStats()
 local pumps=Nexus.ViewProjections.WorkStats().communityPumps
 C.guard(frame:GetScript('OnUpdate')==nil,'Hide detaches the real Community frame update')
 escaped=escaped+Step(H,100)
 local dormant=CB.VirtualStats()
 C.guard(refusals==quiet and dormant.dataFailures==hidden.dataFailures
  and dormant.savedImport.pumps==hidden.savedImport.pumps
  and Nexus.ViewProjections.WorkStats().communityPumps==pumps,
  'hidden failure performs no view retry, projection work or import pump')
 C.guard(CB.DiagnosticSnapshot().blockedReason=='hidden'
  and dormant.lastDataError=='DPS eligibility cursor unavailable',
  'hidden diagnostic retains its failure message')
 CB.Show()
 local shown=refusals
 if not C.setup(shown==quiet+1 and frame:GetScript('OnUpdate')~=nil,
  'Show reattaches updates and observes one newer handled failure') then return end
 escaped=escaped+Step(H,40)
 C.expect(refusals==shown,'reshow failure receives its hold before automatic retry',refusals)
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=begin
 C.guard(Settle(H,CB)~=nil and CB.VirtualStats().lastDataError==nil,
  'restored factory recovers after hidden failure and reshow')
 C.guard(escaped==0 and #H.actions==0 and #H.sent==0,
  'Show/hide failure lifecycle has no escaped frame error, game or network action')
end)

C.scenario('direct-refresh-pending-original-hold',function()
 local H,CB=Boot({value=false},true)
 local begin=Nexus.DpsCapture.BeginCommunityEligibilityCursor
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=function() return nil end
 CB.Show()
 if not C.setup(CB.VirtualStats().dataFailures==1,
  'direct Show has one unnoted handled failure before any frame') then return end
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=begin
 local ready,why=CB.Refresh()
 if not C.setup(ready==false and why=='pending' and CB.DiagnosticSnapshot().projectionPending,
  'direct public refresh provides real healthy pending replacement work') then return end
 local pumps=Nexus.ViewProjections.WorkStats().communityPumps
 local firstWork,escaped=nil,0
 for i=1,70 do
  escaped=escaped+Step(H,1)
  if not firstWork and Nexus.ViewProjections.WorkStats().communityPumps>pumps then firstWork=i end
 end
 print('OBSERVED direct-refresh-pending-original-hold','first-work='..tostring(firstWork))
 C.expect(firstWork and firstWork>=50 and firstWork<=70,
  'unnoted failure holds healthy pending work to the original observed deadline',firstWork)
 C.guard(Settle(H,CB)~=nil and CB.VirtualStats().dataFailures==1
  and CB.VirtualStats().lastDataError==nil,
  'healthy replacement publishes without recharging the old failure count')
 C.guard(escaped==0 and #H.actions==0 and #H.sent==0,
  'direct pending observation sends no game or network action')
end)

C.scenario('safety-probe-cached-throw-retry',function()
 local H,CB=Boot({value=false},true)
 CB.Show()
 if not C.setup(Settle(H,CB)~=nil and not CB.VirtualStats().refreshDirty,
  'published view is clean before the safety-probe cache failure') then return end
 local frame=NexusCommunityBuildsFrame
 local read=Nexus.ViewProjections.BuildsCurrent
 local setText=frame._resultText.SetText
 local reads,throws=0,0
 local probe,cacheCurrent,cleanAtProbe,cleanAtThrow=false,false,false,false
 local message='Synthetic late cached-result refresh exception'
 Nexus.ViewProjections.BuildsCurrent=function(...)
  reads=reads+1
  local current=read(...)
  if not probe then
   probe=true;cacheCurrent=current==true;cleanAtProbe=not CB.VirtualStats().refreshDirty
   return false
  end
  return current
 end
 frame._resultText.SetText=function(self,text)
  if throws==0 and tostring(text):find('Showing ',1,true) then
   throws=throws+1;cleanAtThrow=not CB.VirtualStats().refreshDirty
   error(message,0)
  end
  return setText(self,text)
 end
 local escaped=0
 for _=1,900 do
  if throws>0 then break end
  escaped=escaped+Step(H,1)
 end
 local failed,d=CB.VirtualStats(),CB.DiagnosticSnapshot()
 if not C.setup(probe and cacheCurrent and cleanAtProbe and cleanAtThrow and reads>=2
  and throws==1 and failed.dataFailures==1 and failed.lastDataError==message,
  'real safety probe triggers late host exception after a clean cached list is served') then return end
 C.guard(d.blockedReason=='projection-error' and not d.projectionPending,
  'late cache exception records error and no pending projection')
 C.expect(failed.refreshDirty,'retained late cache exception leaves automatic refresh work dirty')
 Nexus.ViewProjections.BuildsCurrent=read
 frame._resultText.SetText=setText
 local recovered=Settle(H,CB,200)
 local final=CB.VirtualStats()
 print('OBSERVED safety-probe-cached-throw-retry','reads='..reads,
  'dirty-after-failure='..tostring(failed.refreshDirty),'recovered-frames='..tostring(recovered),
  'refreshes='..(final.dataRefreshes-failed.dataRefreshes))
 C.expect(recovered~=nil and final.dataRefreshes>failed.dataRefreshes
  and final.lastDataError==nil and final.dataFailures==1,
  'late cache failure automatically republishes within two seconds without manual invalidation or another probe')
 C.guard(escaped==0 and #H.actions==0 and #H.sent==0,
  'safety-probe failure sends no game or network action')
end)

C.scenario('automatic-refresh-throw-clock-advance',function()
 local H,CB=Boot({value=false},true)
 CB.Show()
 if not C.setup(Settle(H,CB)~=nil,'healthy cache settles before automatic clock-advanced refresh') then return end
 local frame=NexusCommunityBuildsFrame
 local setText=frame._classDropBtn.SetText
 local calls,throws=0,0
 local message='Synthetic clock-advanced automatic refresh exception'
 frame._classDropBtn.SetText=function(self,text)
  calls=calls+1
  if throws==0 then throws=1;H.now=H.now+.6;error(message,0) end
  return setText(self,text)
 end
 CB.MarkDataDirty()
 local escaped=0
 for _=1,100 do
  if throws>0 then break end
  escaped=escaped+Step(H,1)
 end
 local failed=CB.VirtualStats()
 if not C.setup(throws==1 and calls==1 and failed.dataFailures==1 and failed.lastDataError==message,
  'automatic refresh observes one clock-advanced host exception') then return end
 escaped=escaped+Step(H,40)
 local quiet=CB.VirtualStats()
 print('OBSERVED automatic-refresh-throw-clock-advance','calls-after-400ms='..calls,
  'refreshes='..(quiet.dataRefreshes-failed.dataRefreshes))
 C.expect(calls==1 and quiet.dataRefreshes==failed.dataRefreshes,
  'automatic thrown refresh holds retry for 400ms after its observed failure',calls)
 C.guard(Settle(H,CB,200)~=nil and CB.VirtualStats().lastDataError==nil
  and CB.VirtualStats().dataRefreshes>failed.dataRefreshes,
  'clock-advanced automatic refresh eventually republishes')
 C.guard(CB.VirtualStats().dataFailures==1 and escaped==0 and #H.actions==0 and #H.sent==0,
  'automatic clock recovery adds no failure, escaped exception, game or network action')
end)

C.scenario('production-pump-failure-clock-advance',function()
 local H,CB=Boot({value=false},true)
 local read=Nexus.DpsCapture.CommunityEligibilityCursorNext
 local failures=0
 local message='Synthetic clock-advanced production cursor failure'
 Nexus.DpsCapture.CommunityEligibilityCursorNext=function(...)
  if failures==0 then failures=1;H.now=H.now+.6;return false,message end
  return read(...)
 end
 CB.Show()
 local escaped=0
 for _=1,100 do
  if CB.VirtualStats().dataFailures>0 then break end
  escaped=escaped+Step(H,1)
 end
 local failed=CB.VirtualStats()
 if not C.setup(failures==1 and failed.dataFailures==1 and failed.lastDataError==message
  and CB.DiagnosticSnapshot().projectionPending,
  'real clock-advanced cursor failure leaves healthy replacement work pending') then return end
 local pumps=Nexus.ViewProjections.WorkStats().communityPumps
 escaped=escaped+Step(H,40)
 local progress=Nexus.ViewProjections.WorkStats().communityPumps-pumps
 print('OBSERVED production-pump-failure-clock-advance','positive-pumps-after-400ms='..progress)
 C.expect(progress==0,'production cursor failure starts its hold after synchronous work completes',progress)
 C.guard(Settle(H,CB,200)~=nil and Nexus.ViewProjections.WorkStats().communityPumps>pumps
  and CB.VirtualStats().lastDataError==nil,
  'clock-advanced production failure eventually pumps and publishes')
 C.guard(CB.VirtualStats().dataFailures==1 and escaped==0 and #H.actions==0 and #H.sent==0,
  'production clock recovery adds no failure, escaped exception, game or network action')
end)


-- F5 uses 2e9533a as its staged baseline. The import-only ledger contract
-- is an EXPECT, not a setup requirement. WLRB eligibility and real pending
-- import work are checked before the publication regression is measured.
do
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local function IsCurrent(CB)
 local d=CB.DiagnosticSnapshot()
 return d.projectionCurrent and not d.projectionPending and not d.projectionDirty
end
local function IncomingVisible(H,id)
 for _,f in ipairs(H.frames) do
  if f.buildId==id and f:IsVisible() then return true end
 end
 return false
end
local function Sources()
 local out={}
 for level=2,40 do
  local info=debug.getinfo(level,'S');if not info then break end
  out[#out+1]=info.source or '?'
 end
 return table.concat(out,' | ')
end
local function Boot(tag)
 local fx=L.New({players={{name='Existing',class='MAGE',variant=1,title='Existing committed build'}}})
 local db=fx:Install(F.Database())
 db.buildFilters={qualifiedOnly=false,currentClassOnly=true,scope='all',sortMode='dps',page=1,search=''}
 local H=F.Boot(db,function(h) h.playerLevel=60;h.perks.serverBuildSlots={} end)
 local receiving={value=false}
 Nexus.Sync.IsReceiving=function() return receiving.value end
 Nexus.Sync.ReceiveTimeLeft=function() return receiving.value and .5 or 0 end
 local CB=Nexus.CommunityBuilds
 if not C.setup(Nexus.StartupStatus().state=='ready',tag..': actual TOC ready') then return end
 CB.Show()
 local settled
 for i=0,2000 do
  if IsCurrent(CB) and not CB.VirtualStats().savedImport.pending then settled=i;break end
  if i<2000 then Step(H,1) end
 end
 if not C.setup(settled and CB.DiagnosticSnapshot().filterScope=='all'
  and CB.DiagnosticSnapshot().resultCount==1,tag..': warm All scope has exactly one actual published row') then return end
 Step(H,100)
 -- Startup maintenance may still publish revisions after the first view.
 -- Require the actual ready state after the minimum drain; never extend a
 -- product retry deadline or start fault measurement from unfinished setup.
 local drained
 for i=0,1000 do
  if IsCurrent(CB) and not CB.VirtualStats().savedImport.pending
   and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil then drained=i;break end
  if i<1000 then Step(H,1) end
 end
 if not C.setup(drained~=nil and IsCurrent(CB) and not CB.VirtualStats().savedImport.pending
  and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil,
  tag..': warm view stable without a pending revision refresh',
  F.Serialize({drainFrames=drained or false,diagnostic=CB.DiagnosticSnapshot(),
   queuedRefresh=Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key()),import=CB.VirtualStats().savedImport})) then return end
 return H,CB,receiving
end
for _,faulted in ipairs({true,false}) do
 local tag=faulted and 'persistent-import-failure' or 'healthy-import-control'
 C.scenario(tag,function()
  local H,CB,receiving=Boot(tag);if not H then return end
  local importBefore=CB.VirtualStats().savedImport
  local factory=Nexus.BuildCatalog.BeginSavedMirrorCursor
  local faultCalls,firstFaultSources=0,nil
  local faultAt={}
  local message='Synthetic persistent delegated saved-mirror cursor failure'
  if faulted then
   Nexus.BuildCatalog.BeginSavedMirrorCursor=function()
    faultCalls=faultCalls+1
    faultAt[#faultAt+1]=H.now
    if not firstFaultSources then firstFaultSources=Sources() end
    error(message,0)
   end
  end
  -- Public Show creates a fresh real import. Receive deferral makes it
  -- genuinely pending before the cleanup factory is reached.
  receiving.value=true
  CB.Show()
  local pending=CB.VirtualStats().savedImport
  if not C.setup(pending.pending and pending.jobs==importBefore.jobs+1
   and pending.syncDeferrals>importBefore.syncDeferrals and faultCalls==0,
   tag..': public Show owns a new genuine receive-deferred import') then return end
  local escaped=0
  if faulted then
   receiving.value=false
   for _=1,500 do
    if faultCalls>=3 then break end
    escaped=escaped+Step(H,1)
   end
   local d,s=CB.DiagnosticSnapshot(),CB.VirtualStats()
   if not C.setup(faultCalls==3 and s.savedImport.pending
    and firstFaultSources and firstFaultSources:find('core/CommunityController.lua',1,true),
    tag..': three exceptions reach the real delegated import cursor',faultCalls) then return end
   C.expect(s.importFailures==3 and s.lastImportError==message
    and d.savedImportError==true and s.dataFailures==0 and s.lastDataError==nil
    and d.blockedReason~='projection-error',tag..': import error has its own bounded ledger and diagnostic')
  end
  receiving.value=true
  local priorRevision=Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)
  local priorBinds=CB.VirtualStats().dataBinds
  local priorRefreshes=CB.VirtualStats().deferredRefreshes
  local id='import-ledger-incoming'
  local sender='Incoming-Ebonhold'
  -- ViewProjections.IsLoaded requires complete ordinary data even when
  -- qualifiedOnly is false. Use the registered fixture's coherent 79-copy
  -- snapshot and the WLRB pattern in sync_locked_roles_payload.lua:Deliver.
  local ordinary=L.OrdinaryRows(2)
  local verdict=Nexus.LoadoutEvidence.PublicOrdinaryCompleteness({echoes=ordinary})
  if not C.setup(verdict and verdict.complete and L.Copies(ordinary)==79
   and CB.DiagnosticSnapshot().filterQualifiedOnly==false,
   tag..': full incoming ordinary snapshot is eligible without DPS qualification') then return end
  local data={id=id,t='Incoming committed build',a=sender,o=Nexus.Identity.OwnerKey('Incoming','Ebonhold'),
   c='MAGE',m=time()+1,e={}}
  for _,row in ipairs(ordinary) do data.e[#data.e+1]={row.spellId,row.quality,row.stacks} end
  local encoded=Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode(data))
  local total=math.ceil(#encoded/150)
  for i=1,total do
   local wire=string.format('WLRB|%s|%s|%d|%d/%d|%s',sender,id,data.m,i,total,
    encoded:sub((i-1)*150+1,i*150))
   Nexus.Sync.HandleIncoming(wire,sender)
  end
  local committedAt
  for i=0,1500 do
   local row=Nexus.BuildCatalog.Get(id)
   if row and row.title==data.t and Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)>priorRevision then
    committedAt=i;break
   end
   if i<1500 then escaped=escaped+Step(H,1) end
  end
  local admitted=Nexus.BuildCatalog.Get(id)
  local summary=Nexus.BuildCatalog.GetSummary(id)
  if not C.setup(committedAt~=nil and admitted and summary and summary.ordinaryComplete==true
   and Nexus.LoadoutEvidence.PublicOrdinaryCompleteness(admitted).complete
   and L.Copies(admitted.echoes)==79,
   tag..': actual decoder commits a full projection-eligible incoming snapshot and revision',committedAt) then return end
  -- Observe receive=true in the real 250ms status ticker and let the real
  -- revision callback mark Community dirty. Keep the window below the
  -- five-second ViewRefresh maximum receive deferral.
  escaped=escaped+Step(H,30)
  local before=CB.DiagnosticSnapshot()
  if not C.setup(CB.VirtualStats().savedImport.pending and before.filterScope=='all'
   and before.projectionDirty and before.resultCount==1 and not IncomingVisible(H,id),
   tag..': incoming row committed while genuine import and receive-coalesced old publication remain pending') then return end
  local atEnd=H.now
  local pumps=Nexus.ViewProjections.WorkStats().communityPumps
  local firstPublication,firstPump,firstErrorCleared,pendingAtPublication,failuresAtPublication
  local lostImportError=false
  local faultDeltas,requiredHolds={},{}
  local holdsValid=true
  receiving.value=false
  -- No explicit UI action or Refresh after receive-end. Only registered
  -- frame/scheduler paths may request, pump or publish.
  for i=1,2000 do
   escaped=escaped+Step(H,1)
   local d,s=CB.DiagnosticSnapshot(),CB.VirtualStats()
   if faulted and s.savedImport.pending and s.lastImportError~=message then lostImportError=true end
   if not firstPump and Nexus.ViewProjections.WorkStats().communityPumps>pumps then firstPump=i end
   if not firstErrorCleared and faulted and s.lastDataError==nil then firstErrorCleared=i end
   if not firstPublication and s.dataBinds>priorBinds and IncomingVisible(H,id) and d.resultCount==2 then
    firstPublication=i;pendingAtPublication=s.savedImport.pending;failuresAtPublication=s.dataFailures
   end
  end
  for i=2,#faultAt do
   local elapsed=faultAt[i]-faultAt[i-1]
   local required=math.min(.5*(2^math.min(i-2,4)),8)
   faultDeltas[#faultDeltas+1]=elapsed;requiredHolds[#requiredHolds+1]=required
   if elapsed<required-1e-7 then holdsValid=false end
  end
  local d,s=CB.DiagnosticSnapshot(),CB.VirtualStats()
  C.guard(Nexus.BuildCatalog.Get(id)~=nil,tag..': incoming committed catalog row survives observation')
  C.guard(escaped==0,tag..': all import failures stay inside production frame containment',escaped)
  C.guard(#H.actions==0 and #H.sent==0,tag..': no synthetic game/network send',#H.sent)
  if not faulted then
   C.expect(firstPublication and not s.savedImport.pending and IsCurrent(CB)
    and s.savedImport.completions==importBefore.completions+1,
    tag..': healthy import completes and actual incoming card publishes automatically',firstPublication)
  else
   C.guard(faultCalls>3 and s.savedImport.pending,tag..': persistent fault remains real and retries over 20 seconds',faultCalls)
  end
  print('OBSERVED',tag,F.Serialize({receivedFullSnapshot=true,incomingOrdinaryComplete=true,
   incomingCopies=79,catalogCommitted=true,
   committedFrames=committedAt,receiveEnd=atEnd,observationFrames=2000,
   firstPublicationFrame=firstPublication or false,firstPumpFrame=firstPump or false,
   importPendingAtPublication=pendingAtPublication==nil and 'no-publication' or pendingAtPublication,
   failuresAtPublication=failuresAtPublication or false,errorClearedFrame=firstErrorCleared or false,
   incomingVisibleAtEnd=IncomingVisible(H,id),resultCount=d.resultCount,blockedReason=d.blockedReason,
   projectionCurrent=d.projectionCurrent,projectionPending=d.projectionPending,projectionDirty=d.projectionDirty,
   importPending=s.savedImport.pending,importPhase=s.savedImport.pendingPhase or 'none',
   importCompletions=s.savedImport.completions-importBefore.completions,faultCalls=faultCalls,
   faultAt=faultAt,faultDeltas=faultDeltas,requiredHolds=requiredHolds,
   importFailures=s.importFailures or false,lastImportError=s.lastImportError or false,
   dataFailures=s.dataFailures,deferredRefreshes=s.deferredRefreshes-priorRefreshes,
   dataBinds=s.dataBinds-priorBinds,positivePumps=Nexus.ViewProjections.WorkStats().communityPumps-pumps,
   lastDataError=s.lastDataError or false,actions=#H.actions,sent=#H.sent,escaped=escaped}))
  if faulted then
   C.expect(firstPublication and firstPublication<500 and pendingAtPublication==true
    and firstPump and IncomingVisible(H,id) and IsCurrent(CB),
    tag..': All publishes the actual incoming card before the safety probe while import remains pending',firstPublication)
   C.expect(not lostImportError and s.lastImportError==message and s.importFailures==faultCalls
    and d.savedImportError==true and s.dataFailures==0 and s.lastDataError==nil,
    tag..': successful All publication never erases or reclassifies the import failure')
   C.guard(#faultAt==faultCalls and #faultAt>=4,
    tag..': every real factory fault has an observed timestamp')
   C.expect(holdsValid,tag..': adjacent actual faults respect each independent exponential hold',F.Serialize(faultDeltas))
   C.expect(faultAt[4] and faultAt[3] and faultAt[4]-faultAt[3]>=2-1e-7,
    tag..': third-to-fourth fault includes receive admission time in its two-second hold',
    faultAt[4] and faultAt[4]-faultAt[3])
  end
  C.guard((s.savedImport.maxWorkPerPump or 0)<=25,tag..': each real import pump respects its work budget')
  Nexus.BuildCatalog.BeginSavedMirrorCursor=factory
  if faulted then
   local repaired=Settle(H,CB,2000)
   local final=CB.VirtualStats()
   C.expect(repaired and final.savedImport.completions==importBefore.completions+1
    and final.savedImport.jobs==importBefore.jobs+1 and final.lastImportError==nil
    and CB.DiagnosticSnapshot().savedImportError==false and final.importFailures==faultCalls,
    tag..': restoring the real factory completes the original import once and clears only its current error',repaired)
   C.guard(final.savedImport.workUnits>s.savedImport.workUnits and IncomingVisible(H,id)
    and #H.actions==0 and #H.sent==0,tag..': recovery performs real import work and retains the incoming publication')
  end
 end)
end

C.scenario('held-import-hide-show-dormancy',function()
 local H,CB,receiving=Boot('held-import-hide-show');if not H then return end
 local before=CB.VirtualStats().savedImport
 local factory=Nexus.BuildCatalog.BeginSavedMirrorCursor
 local calls=0
 local message='Synthetic held import before hiding'
 Nexus.BuildCatalog.BeginSavedMirrorCursor=function() calls=calls+1;error(message,0) end
 receiving.value=true;CB.Show()
 if not C.setup(CB.VirtualStats().savedImport.pending and CB.VirtualStats().savedImport.jobs==before.jobs+1,
  'hide case owns a real receive-deferred import') then return end
 receiving.value=false
 local escaped=0
 for _=1,200 do if calls>0 then break end;escaped=escaped+Step(H,1) end
 if not C.setup(calls==1 and CB.VirtualStats().savedImport.pending,
  'hide case reaches a real import factory exception') then return end
 local frame=NexusCommunityBuildsFrame
 frame._myBuildsBtn:Click()
 local failed=CB.VirtualStats()
 C.expect(CB.DiagnosticSnapshot().blockedReason=='saved-import-error'
  and CB.DiagnosticSnapshot().savedImportError==true and failed.dataFailures==0 and failed.lastDataError==nil
  and failed.lastImportError==message,'Mine reports its import failure independently of projection status')
 CB.Hide()
 local hidden=CB.VirtualStats()
 local pumps=Nexus.ViewProjections.WorkStats().communityPumps
 local independent=0
 Nexus.Scheduler.After('test.hidden-import-witness',.05,function() independent=independent+1 end)
 escaped=escaped+Step(H,100)
 local dormant=CB.VirtualStats()
 C.guard(frame:GetScript('OnUpdate')==nil and CB.DiagnosticSnapshot().blockedReason=='hidden'
  and dormant.savedImport.pumps==hidden.savedImport.pumps
  and dormant.savedImport.workUnits==hidden.savedImport.workUnits
  and dormant.dataBinds==hidden.dataBinds and Nexus.ViewProjections.WorkStats().communityPumps==pumps
  and calls==1 and independent==1,'hidden frame stops view/import work while the independent scheduler runs')
 C.expect(dormant.lastImportError==message and dormant.importFailures==1,
  'hidden dormancy retains the import failure evidence')
 Nexus.BuildCatalog.BeginSavedMirrorCursor=factory
 receiving.value=true;CB.Show()
 local shown=CB.VirtualStats()
 C.guard(type(frame:GetScript('OnUpdate'))=='function' and shown.savedImport.pending
  and shown.savedImport.jobs==before.jobs+1,'Show resumes the same real pending import')
 C.expect(shown.lastImportError==message,'reshow alone does not clear an unfinished import failure')
 receiving.value=false
 escaped=escaped+Step(H,1)
 local advanced=CB.VirtualStats()
 C.guard(advanced.savedImport.pumps>shown.savedImport.pumps and advanced.savedImport.workUnits>shown.savedImport.workUnits,
  'restored import advances real work on the first visible frame')
 local settled=Settle(H,CB,2000)
 local final=CB.VirtualStats()
 C.expect(settled and final.savedImport.completions==before.completions+1
  and final.savedImport.jobs==before.jobs+1 and final.lastImportError==nil and final.importFailures==1
  and CB.DiagnosticSnapshot().savedImportError==false,'reshown import completes exactly once and clears its error after success')
 C.guard(final.dataBinds>hidden.dataBinds and Nexus.ViewProjections.WorkStats().communityPumps>pumps,
  'reshow recovers positive view projection work and publication')
 C.guard(escaped==0 and #H.actions==0 and #H.sent==0,'hide/show recovery sends no game or network action')
end)

-- S1 uses f3b00aed as its baseline. Normal opens stay nonreceiving:
-- neither the initial fault nor the held reopen is hidden by sync deferral.
for _,warm in ipairs({false,true}) do
 local tag=warm and 'normal-reopen-import-fault' or 'cold-open-import-fault'
 C.scenario(tag,function()
  local H,CB,receiving
  if warm then
   H,CB,receiving=Boot(tag);if not H then return end
   CB.Hide()
  else
   local fx=L.New({players={{name='Existing',class='MAGE',variant=1,title='Existing committed build'}}})
   local db=fx:Install(F.Database())
   db.buildFilters={qualifiedOnly=false,currentClassOnly=true,scope='all',sortMode='dps',page=1,search=''}
   H=F.Boot(db,function(h) h.playerLevel=60;h.perks.serverBuildSlots={} end)
   CB=Nexus.CommunityBuilds;receiving={value=false}
   Nexus.Sync.IsReceiving=function() return receiving.value end
  end
  local before=CB.VirtualStats()
  if not C.setup(Nexus.StartupStatus().state=='ready' and not CB.IsShown()
   and not before.savedImport.pending and not Nexus.Sync.IsReceiving(),
   tag..': real startup and hidden nonreceiving open prerequisites reached') then return end
  local factory=Nexus.BuildCatalog.BeginSavedMirrorCursor
  local calls,at=0,{}
  local message='Synthetic normal-open saved cursor failure'
  Nexus.BuildCatalog.BeginSavedMirrorCursor=function()
   calls=calls+1;at[#at+1]=H.now;error(message,0)
  end
  local ok,err=pcall(CB.Show)
  local failed=CB.VirtualStats()
  if not C.setup(calls==1 and failed.savedImport.pending
   and failed.savedImport.jobs==before.savedImport.jobs+1,
   tag..': public Show reaches one real pending-job cleanup exception') then return end
  C.expect(ok and CB.IsShown(),tag..': import exception is contained and the Library opens',err)
  C.expect(failed.importFailures==before.importFailures+1 and failed.lastImportError==message
   and failed.dataFailures==before.dataFailures and CB.DiagnosticSnapshot().savedImportError,
   tag..': open-time failure enters the independent import ledger exactly once')
  CB.Hide()
  local escaped=Step(H,10)
  local hidden=CB.VirtualStats()
  C.guard(calls==1 and hidden.savedImport.pumps==failed.savedImport.pumps,
   tag..': hidden frames do not retry the failed import')
  local reopen,reopenErr=pcall(CB.Show)
  C.expect(reopen and CB.IsShown() and calls==1,
   tag..': normal reopen inside the hold opens without an early import retry',reopenErr)
  escaped=escaped+Step(H,30)
  C.expect(calls==1 and CB.VirtualStats().lastImportError==message,
   tag..': hide and reopen preserve the original first400ms hold')
  escaped=escaped+Step(H,160)
  local published=CB.VirtualStats()
  C.expect(CB.IsShown() and IsCurrent(CB) and CB.DiagnosticSnapshot().resultCount==1
   and published.dataBinds>before.dataBinds and published.savedImport.pending,
   tag..': All automatically publishes committed data while the import still fails')
  C.expect(calls>=2 and at[2]-at[1]>=.5-1e-7
   and published.importFailures==before.importFailures+calls and published.lastImportError==message,
   tag..': real retries occur only after their hold and preserve error evidence',F.Serialize(at))
  Nexus.BuildCatalog.BeginSavedMirrorCursor=factory
  local recovered=Settle(H,CB,2000)
  local final=CB.VirtualStats()
  C.expect(recovered and final.savedImport.completions==before.savedImport.completions+1
   and final.savedImport.jobs==before.savedImport.jobs+1 and final.lastImportError==nil
   and CB.DiagnosticSnapshot().savedImportError==false,
   tag..': restored cursor completes the original job exactly once without another Show',recovered)
  C.guard(final.savedImport.workUnits>failed.savedImport.workUnits and final.savedImport.maxWorkPerPump<=25
   and escaped==0 and #H.actions==0 and #H.sent==0,
   tag..': recovery performs bounded real work without escaped frame errors or game/network actions')
 end)
end

C.scenario('open-import-begin-failure-before-job',function()
 local H,CB,receiving=Boot('begin-before-job');if not H then return end
 CB.Hide()
 local before=CB.VirtualStats()
 local slots=Nexus.GameAdapter.Slots
 local calls,origins=0,{}
 local message='Synthetic saved import Begin dependency failure'
 Nexus.GameAdapter.Slots=function(...)
  local caller=debug.getinfo(2,'S')
  if caller and caller.source:find('core/CommunityController.lua',1,true) then
   calls=calls+1;origins[#origins+1]=Sources();error(message,0)
  end
  return slots(...)
 end
 local ok,err=pcall(CB.Show)
 local failed=CB.VirtualStats()
 if not C.setup(calls==1 and not failed.savedImport.pending
  and failed.savedImport.jobs==before.savedImport.jobs and not Nexus.Sync.IsReceiving(),
  'normal Show reaches a Begin dependency failure before a real job exists') then return end
 C.expect(ok and CB.IsShown() and failed.lastImportError==message and failed.importFailures==before.importFailures+1,
  'pre-job Begin failure opens the Library and retains import evidence',err)
 C.expect(CB.DiagnosticSnapshot().savedImportPending==false and CB.DiagnosticSnapshot().savedImportError==true,
  'retry intent never masquerades as an existing import job')
 local escaped=Step(H,40)
 C.expect(calls==1 and CB.VirtualStats().lastImportError==message,
  'no-job observation cannot erase Begin error or bypass its first400ms hold')
 -- The genuine Mine control must reflect the unresolved import request even
 -- though no controller job exists; it must not manufacture a pending flag.
 if CB.IsShown() then NexusCommunityBuildsFrame._myBuildsBtn:Click() end
 C.expect(CB.DiagnosticSnapshot().filterScope=='mine'
  and CB.DiagnosticSnapshot().blockedReason=='saved-import-error'
  and CB.DiagnosticSnapshot().savedImportPending==false,
  'Mine reports unresolved Begin error separately from actual job pending')
 -- A normal no-source refusal is still not a completed import. Keep the
 -- original failure while the real Begin returns false without a new error.
 local refused=0
 local refusalFinished
 Nexus.GameAdapter.Slots=function(...)
  local caller=debug.getinfo(2,'S')
  if caller and caller.source:find('core/CommunityController.lua',1,true) then
   refused=refused+1
   if refused==1 then H.now=H.now+.6;refusalFinished=H.now end
   return nil
  end
  return slots(...)
 end
 for _=1,100 do
  if refused>0 then break end
  escaped=escaped+Step(H,1)
 end
 local mineRefreshes=0
 local frame=NexusCommunityBuildsFrame
 local setText=frame and frame._classDropBtn.SetText
 if setText then
  frame._classDropBtn.SetText=function(self,text)
   mineRefreshes=mineRefreshes+1;return setText(self,text)
  end
 end
 escaped=escaped+Step(H,40)
 C.expect(refused==1 and not CB.VirtualStats().savedImport.pending
  and CB.VirtualStats().savedImport.jobs==before.savedImport.jobs
  and CB.VirtualStats().lastImportError==message and CB.VirtualStats().importFailures==before.importFailures+1,
  'a clock-advanced refused Begin preserves its error and full first400ms hold',refused)
 C.expect(refusalFinished and setText and mineRefreshes==0,
  'Mine does not request ordinary refreshes while unresolved Begin intent is held',mineRefreshes)
 if setText then frame._classDropBtn.SetText=setText end
 print('OBSERVED refused-Begin-clock-hold',F.Serialize({refusals=refused,
  refusalFinished=refusalFinished,observedAt=H.now,mineRefreshes=mineRefreshes}))
 Nexus.GameAdapter.Slots=slots
 local recovered=Settle(H,CB,2000)
 local final=CB.VirtualStats()
 C.expect(recovered and final.savedImport.jobs==before.savedImport.jobs+1
  and final.savedImport.completions==before.savedImport.completions+1
  and final.lastImportError==nil and final.importFailures==before.importFailures+1,
  'restoring Begin dependency automatically starts and completes exactly one real job',recovered)
 C.guard(final.savedImport.pumps>before.savedImport.pumps and final.savedImport.workUnits>before.savedImport.workUnits
  and escaped==0 and #H.actions==0 and #H.sent==0,
  'Begin recovery advances real work with no frame exception or game/network action')
 print('OBSERVED Begin-failure-origin',F.Serialize(origins))
end)
end

C.finish('(public failure hold and recovery; synthetic host only)')
