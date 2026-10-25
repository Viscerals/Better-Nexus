-- Real TOC, Community facade/controller/projection factory and registered frame.
-- Faults use public dependencies or synthetic host methods except the detail-Finish
-- refusal arms, which replace a private controller method and invoke its captured
-- callback. Some setup/guard observations inspect private upvalues. Renderer, List
-- and PumpBuilds functions are not replaced. Error-history checks concern synthetic
-- addon records; they establish no native timing or native error-frame outcome.
-- Checker classifications use staged baselines: original failure/receive/import
-- regressions against 1f993d7; explicit-query latency and handled-message cases
-- against 1be520d; failed explicit-request timing and thrown-message cases against
-- 8e03747. Later SETUPs may rely on earlier retained-error repairs. Setup and check
-- classifications also evolved with those repairs; exact supersession comparisons
-- remain in the PR evidence. Removed expectations are the two replacement-message
-- cases, superseded by post-hold timing and truthful cancelled-job checks, and the
-- old cold-Mine receive writes>0 guard. The Mine wait now requires zero writes/pumps;
-- final-f3-all-cold-receive-progresses retains the All progression predicate.
-- The dirty-notifications Mine arm establishes its actual fault through explicit
-- Refresh: correct no-churn waiting no longer triggers that setter automatically.
-- Its original hold/safety/import assertions remain unchanged.
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
 -- R2 now correctly forbids the old automatic cold-Mine refresh trigger.
 -- Establish the real view failure explicitly, then keep the original
 -- same-context dirty-notification hold, import and safety predicates below.
 local faulted,fault=pcall(CB.Refresh)
 C.setup(not faulted and attempts==1 and type(fault)=='string'
  and fault:find('Synthetic dirty-event render failure',1,true)
  and CB.VirtualStats().savedImport.pending,
  'explicit Refresh establishes actual Mine view failure before dirty notifications')
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
 -- Supersedes the original writes>0 Mine predicate (retained in frozen a7
 -- evidence): R2 requires Mine to wait without full-refresh churn. Actual All
 -- cold-receive cadence/progression has a separate positive successor below.
 C.expect(writes==0 and projectionPumps==0,
  'cold Mine receive waits for import without full-refresh or projection churn',writes)
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
 CB.Refresh() -- Explicit request supplies real pending work during the existing hold.
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
 Step(H,100)
 C.setup(Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil and CB.DiagnosticSnapshot().projectionCurrent
  and not CB.VirtualStats().refreshDirty,'startup view scheduler is drained before arming safety-only observation')
 local frame=NexusCommunityBuildsFrame
 local callback=frame:GetScript('OnUpdate');local probeFromFrame=false
 local read=Nexus.ViewProjections.BuildsCurrent
 local setText=frame._resultText.SetText
 local reads,throws=0,0
 local probe,cacheCurrent,cleanAtProbe,cleanAtThrow=false,false,false,false
 local message='Synthetic late cached-result refresh exception'
 Nexus.ViewProjections.BuildsCurrent=function(...)
  reads=reads+1
  local current=read(...)
  if not probe then
   for i=2,50 do local info=debug.getinfo(i,'f');if not info then break end;if info.func==callback then probeFromFrame=true end end
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
 C.guard(probeFromFrame,'currentness failure is observed through the actual registered Library safety callback')
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
 CB.Refresh() -- Explicit pending request preserves the completion-anchored hold.
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



-- Queued-import callback failures use 7e6c81f5 as their staged baseline.
-- A real nonempty Saved slot produces a real pending catalog ticket; the
-- host fault is armed only after that ticket exists and at actual commit.
C.scenario('saved-catalog-completion-refresh-throw',function()
 local receiving={value=true}
 local H,CB=Boot(receiving)
 local catalog=Nexus.BuildCatalog
 local put=catalog.Put
 local ticket,mirrorId
 catalog.Put=function(record,...)
  local ok,why,pending=put(record,...)
  if record.importedSavedBuild and ok==nil and why=='ROOT_MUTATION_PENDING' then
   ticket=pending;mirrorId=record.id
  end
  return ok,why,pending
 end
 CB.Show();NexusCommunityBuildsFrame._myBuildsBtn:Click()
 local before=CB.VirtualStats().savedImport
 local callbackFailures=catalog.DebugStats().mutationCompletionFailures
 if not C.setup(before.pending and before.pumps==0,
  'nonempty Saved slot is genuinely deferred before creating a catalog write') then return end
 receiving.value=false
 local escaped=0
 for _=1,2000 do
  if ticket then break end
  escaped=escaped+Step(H,1)
 end
 local waiting=CB.VirtualStats().savedImport
 if not C.setup(type(ticket)=='table' and ticket.state=='pending' and waiting.pending
  and waiting.catalogPutCalls==before.catalogPutCalls+1,
  'real Saved import produced one pending catalog mutation ticket') then return end
 local frame=NexusCommunityBuildsFrame
 local setText=frame._classDropBtn.SetText
 local throws,callbackOrigin=0,false
 local message='Synthetic saved-ticket completion Refresh exception'
 frame._classDropBtn.SetText=function(self,text)
  if ticket.committed==true then
   throws=throws+1
   local stack={}
   for i=2,30 do
    local info=debug.getinfo(i,'S');if not info then break end
    stack[#stack+1]=info.source
   end
   local origin=table.concat(stack,' | ')
   if origin:find('core/CommunityController.lua',1,true)
    and origin:find('core/BuildCatalog.lua',1,true) then callbackOrigin=true end
   error(message,0)
  end
  return setText(self,text)
 end
 for _=1,2000 do
  if ticket.state~='pending' and throws>0 then break end
  escaped=escaped+Step(H,1)
 end
 local failed=CB.VirtualStats()
 if not C.setup(ticket.committed==true and throws>0 and callbackOrigin,
  'delegated SetText fault is reached by the real committed-ticket controller callback') then return end
 C.expect(failed.dataFailures==1 and failed.lastDataError==message
  and failed.importFailures==0 and failed.lastImportError==nil,
  'ticket callback retains a view failure without misclassifying the successful import write')
 C.expect(catalog.DebugStats().mutationCompletionFailures==callbackFailures,
  'view failure does not abort the catalog completion callback')
 escaped=escaped+Step(H,40)
 local held=CB.VirtualStats()
 C.expect(held.dataRefreshes==failed.dataRefreshes and held.lastDataError==message
  and held.dataFailures==1,'callback failure preserves its publication hold and error for400ms')
 C.guard(catalog.Get(mirrorId)~=nil and ticket.committed==true,
  'Saved mirror is genuinely committed despite the delegated display fault')
 frame._classDropBtn.SetText=setText
 catalog.Put=put
 local recovered=Settle(H,CB,2000)
 local final=CB.VirtualStats()
 C.expect(recovered and not final.savedImport.pending
  and final.savedImport.completions==before.completions+1
  and final.savedImport.catalogPutCalls==before.catalogPutCalls+1
  and final.savedImport.writes==before.writes+1,
  'restored display lets the original real import complete once without resubmitting its ticket',recovered)
 C.expect(final.lastDataError==nil and CB.DiagnosticSnapshot().projectionCurrent
  and final.dataBinds>failed.dataBinds,
  'automatic projection work eventually republishes after callback failure')
 C.guard(final.savedImport.maxWorkPerPump<=25 and escaped==0 and #H.actions==0 and #H.sent==0,
  'catalog callback recovery stays bounded and causes no frame escape or game/network action')
 print('OBSERVED saved-ticket-refresh',F.Serialize({throws=throws,callbackOrigin=callbackOrigin,
  ticketCommitted=ticket.committed,pending=final.savedImport.pending,
  completions=final.savedImport.completions-before.completions,
  callbackFailures=catalog.DebugStats().mutationCompletionFailures-callbackFailures,
  dataFailures=final.dataFailures,importFailures=final.importFailures,recoveredFrames=recovered or false}))
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

-- F1 queued healthy-import fairness uses7e6c81f as its baseline.
-- Select the documented no-profiler catalog fallback only for this case.
do
-- F1: healthy nonempty saved import across real receive-end publication.
-- Supported no-profiler pacing makes actual catalog tickets observable.
-- No renderer/projection/import replacement, pending-state fabrication,
-- private callback invocation, catalog-pump shortcut or injected exception.
local T=dofile('tests/prototype/startup_support.lua')
local restorePacing=T.SingleSlicePacing()
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local tag='registered-queued-import'
local function Current(CB)
 local d=CB.DiagnosticSnapshot()
 return d.projectionCurrent and not d.projectionPending and not d.projectionDirty
end
local function Visible(H,id)
 for _,f in ipairs(H.frames) do if f.buildId==id and f:IsVisible() then return true end end
 return false
end
C.scenario('healthy-nonempty-import-receive-end',function()
 local fx=L.New({players={{name='Existing',class='MAGE',variant=1,title='Existing shared build'}}})
 local db=fx:Install(F.Database())
 db.buildFilters={qualifiedOnly=false,currentClassOnly=true,scope='all',sortMode='recent',page=1,search=''}
 local H=F.Boot(db,function(h)
  h.playerLevel=60;h.perks.serverActiveSlot=1
  h.perks.serverBuildSlots={[1]={name='Original saved build',verified=true,echoes=L.OrdinaryRows(3)}}
 end)
 local CB,CAT=Nexus.CommunityBuilds,Nexus.BuildCatalog
 local receiving={value=false}
 Nexus.Sync.IsReceiving=function() return receiving.value end
 Nexus.Sync.ReceiveTimeLeft=function() return receiving.value and .5 or 0 end
 local openFrames,escaped=0,0
 local function Step(n)
  for _=1,n do
   if not pcall(H.Advance,.01,.01) then escaped=escaped+1 end
   openFrames=openFrames+1
  end
 end
 local function State()
  local s,d,w=CB.VirtualStats(),CB.DiagnosticSnapshot(),Nexus.ViewProjections.WorkStats()
  return {time=H.now,frame=openFrames,importPending=s.savedImport.pending,
   importJobs=s.savedImport.jobs,importPumps=s.savedImport.pumps,importWork=s.savedImport.workUnits,
   importCompletions=s.savedImport.completions,importWrites=s.savedImport.writes,
   importFinalizations=s.savedImport.finalizations,importCatalogPuts=s.savedImport.catalogPuts,
   importFailures=s.importFailures or 0,lastImportError=s.lastImportError or false,
   dataFailures=s.dataFailures,dataBinds=s.dataBinds,deferredRefreshes=s.deferredRefreshes,
   communityPumps=w.communityPumps,sourceRows=w.sourceRows,
   projectionDirty=d.projectionDirty,projectionPending=d.projectionPending,
   projectionCurrent=d.projectionCurrent,resultCount=d.resultCount,reason=d.blockedReason}
 end
 if not C.setup(Nexus.StartupStatus().state=='ready' and debugprofilestop==nil,
  'actual TOC ready under documented single-slice catalog fallback') then return end
 CB.Show()
 local settled
 for i=0,4000 do
  if Current(CB) and not CB.VirtualStats().savedImport.pending then settled=i;break end
  if i<4000 then Step(1) end
 end
 Step(100)
 for _=1,1000 do
  if Current(CB) and not CB.VirtualStats().savedImport.pending
   and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil then break end
  Step(1)
 end
 local mirror
 for _,b in pairs(CB.Builds()) do
  if b.importedSavedBuild and b.serverSlot==1 then mirror=b end
 end
 if not C.setup(settled~=nil and mirror and CAT.Get(mirror.id)
  and Current(CB) and not CB.VirtualStats().savedImport.pending
  and CB.DiagnosticSnapshot().filterScope=='all'
  and CB.DiagnosticSnapshot().resultCount>=1
  and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil,
  'warm actual All publication and real completed nonempty saved mirror') then return end
 local before=State()
 local originalPut=CAT.Put
 local ticket,puts={},{ }
 -- Transparent observation only: preserve all return values and invoke no
 -- completion callbacks. The import itself obtains and owns the real ticket.
 CAT.Put=function(record,...)
  local ok,why,pending=originalPut(record,...)
  if type(record)=='table' and record.importedSavedBuild then
   puts[#puts+1]={frame=openFrames,time=H.now,id=record.id,title=record.title,
    why=why or false,ok=ok==nil and 'nil' or ok,
    pending=type(pending)=='table' and pending.state=='pending',
    trace=debug.traceback('real saved-mirror Put',2)}
   if type(pending)=='table' then ticket=pending end
  end
  return ok,why,pending
 end
 receiving.value=true
 H.perks.serverBuildSlots[1]={name='Changed healthy saved build',verified=true,echoes=L.OrdinaryRows(4)}
 local changedSource=F.Serialize(H.perks.serverBuildSlots)
 H.Notify();Nexus.GameAdapter.Poll();CB.Hide();CB.Show()
 openFrames=0
 local opened=State()
 if not C.setup(opened.importPending and opened.importJobs==before.importJobs+1
  and CB.VirtualStats().savedImport.syncDeferrals>0 and #puts==0,
  'public reopen starts a real changed nonempty import and receive defers its work') then return end
 local id,sender='receive-completion-incoming','Incoming-Ebonhold'
 local ordinary=L.OrdinaryRows(2)
 if not C.setup(L.Copies(ordinary)==79 and Nexus.LoadoutEvidence.PublicOrdinaryCompleteness({echoes=ordinary}).complete,
  'incoming full snapshot has coherent complete 79-copy ordinary evidence') then return end
 local data={id=id,t='Incoming complete shared build',a=sender,o=Nexus.Identity.OwnerKey('Incoming','Ebonhold'),
  c='MAGE',m=time()+1,e={}}
 for _,row in ipairs(ordinary) do data.e[#data.e+1]={row.spellId,row.quality,row.stacks} end
 local priorRevision=Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)
 local encoded=Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode(data))
 local total=math.ceil(#encoded/150)
 for i=1,total do
  Nexus.Sync.HandleIncoming(string.format('WLRB|%s|%s|%d|%d/%d|%s',sender,id,data.m,i,total,
   encoded:sub((i-1)*150+1,i*150)),sender)
 end
 local committed
 for i=0,450 do
  local b=CAT.Get(id)
  if b and b.title==data.t and Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)>priorRevision then committed=i;break end
  if i<450 then Step(1) end
 end
 local incoming=CAT.Get(id)
 if not C.setup(committed~=nil and incoming and CAT.GetSummary(id).ordinaryComplete==true
  and L.Copies(incoming.echoes)==79,
  'actual Sync decoder commits full incoming row before receive closes',committed) then return end
 Step(30)
 -- Hide/Show reset the real status and safety tickers. Align to just before
 -- an ordinary 250ms status turn without invoking its callback ourselves.
 while openFrames%25~=24 do Step(1) end
 local beforeEnd=State()
 if not C.setup(openFrames<500 and beforeEnd.importPending and beforeEnd.projectionDirty
  and not beforeEnd.projectionPending and not Visible(H,id) and #puts==0,
  'real revision route dirties old publication while receive and changed import remain pending',F.Serialize(beforeEnd)) then return end
 receiving.value=false
 local endFrame,endTime=openFrames,H.now
 Step(1)
 local first=State()
 local firstPump,firstRequest,firstPublication,firstTicket,firstTicketCommit,firstCompletion
 local publicationPending,publicationTicketPending,preCommitPumps= false,false,0
 local lastPumps=beforeEnd.communityPumps
 local events={}
 local function Observe()
  local s=State();local f=openFrames-endFrame
  local pending=ticket.state=='pending'
  if not firstTicket and pending then firstTicket=f;events[#events+1]={event='ticket-pending',frame=f,state=s} end
  if not firstTicketCommit and ticket.state=='committed' then firstTicketCommit=f;events[#events+1]={event='ticket-committed',frame=f,state=s} end
  if not firstCompletion and not s.importPending then firstCompletion=f;events[#events+1]={event='import-complete',frame=f,state=s} end
  if not firstRequest and s.projectionPending then firstRequest=f;events[#events+1]={event='projection-request',frame=f,state=s} end
  if s.communityPumps>lastPumps then
   if not firstPump then firstPump=f;events[#events+1]={event='positive-projection-pump',frame=f,state=s} end
   if pending then preCommitPumps=preCommitPumps+s.communityPumps-lastPumps end
  end
  lastPumps=s.communityPumps
  if not firstPublication and s.dataBinds>beforeEnd.dataBinds and Visible(H,id) then
   firstPublication=f;publicationPending=s.importPending;publicationTicketPending=pending
   events[#events+1]={event='incoming-visible',frame=f,state=s,ticketPending=pending}
  end
 end
 Observe()
 -- Never reach the 8-second safety ticker after this reopen. Let the actual
 -- lifecycle finish the genuine ticket and import as a healthy control.
 for _=1,600 do
  if openFrames>=740 then break end
  if firstPublication and firstCompletion and ticket.state=='committed' and Current(CB) then break end
  Step(1);Observe()
 end
 local final=State()
 C.setup(#puts==1 and puts[1].why=='ROOT_MUTATION_PENDING' and puts[1].pending
  and firstTicket and firstTicketCommit and firstTicketCommit>firstTicket,
  'changed slot creates one genuine pending catalog ticket that later commits',F.Serialize(puts))
 C.expect(firstPump and firstTicketCommit and firstPump<firstTicketCommit,
  'All projection performs positive work before healthy saved-mirror commit',firstPump)
 C.expect(firstPublication and publicationPending and publicationTicketPending,
  'actual incoming card publishes while healthy saved import and its real ticket remain pending',firstPublication)
 C.expect(preCommitPumps>=2 and firstPublication and firstPublication<=50,
  'real multi-step All projection publishes within500ms while catalog work continues',preCommitPumps)
 C.guard(first.importWork>beforeEnd.importWork and first.importPumps>beforeEnd.importPumps
  and CB.VirtualStats().savedImport.maxWorkPerPump<=25,
  'due healthy import advances on the first receive-end frame within its25-unit budget')
 C.guard(firstTicketCommit and firstCompletion and not final.importPending
  and final.importCompletions==before.importCompletions+1 and final.importJobs==before.importJobs+1
  and CAT.Get(mirror.id).serverTitle=='Changed healthy saved build',
  'healthy import finishes exactly once and commits the actual changed saved mirror')
 C.guard(firstPublication and Visible(H,id) and Current(CB),
  'incoming complete row ultimately publishes through production scheduling')
 C.guard(openFrames<800,'observation ends before the 8-second safety probe can run',openFrames)
 C.guard(final.dataFailures==0 and final.importFailures==0 and escaped==0,
  'healthy scenario contains no injected or escaped fault')
 C.guard(F.Serialize(H.perks.serverBuildSlots)==changedSource and #H.actions==0 and #H.sent==0,
  'source saved-slot payload is unchanged; no synthetic game action or network send')
 print('OBSERVED_F1',tag,F.Serialize({before=before,opened=opened,incomingCommitFrames=committed,
  receiveEndFrame=endFrame,receiveEndTime=endTime,beforeEnd=beforeEnd,firstFrame=first,
  firstFrameImportWork=first.importWork-beforeEnd.importWork,
  firstRequestFrame=firstRequest or false,firstPumpFrame=firstPump or false,
  firstTicketFrame=firstTicket or false,firstTicketCommitFrame=firstTicketCommit or false,
  firstPublicationFrame=firstPublication or false,firstImportCompletionFrame=firstCompletion or false,
  publicationWhileImportPending=publicationPending,publicationWhileTicketPending=publicationTicketPending,
  positivePumpsWhileTicketPending=preCommitPumps,events=events,puts=puts,final=final,
  sourceRowsAdded=final.sourceRows-beforeEnd.sourceRows,actions=#H.actions,sent=#H.sent,
  noSafetyProbe=openFrames<800,escaped=escaped}))
 CAT.Put=originalPut
end)
restorePacing()
end

-- Shared refresh-boundary regressions use f0b7c2ba as their baseline.
C.scenario('natural-view-refresh-hold',function()
-- Independent natural revision/scheduler path; no renderer/pump/callback replacement.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local H=F.Boot(F.Database(),function(h) h.playerLevel=60;h.perks.serverBuildSlots={};h.perks.serverActiveSlot=1 end)
local CB,CAT,A=Nexus.CommunityBuilds,Nexus.BuildCatalog,Nexus.GameAdapter
local escaped=0
local function Step(n) for _=1,n do local ok,e=pcall(H.Advance,.01,.01);if not ok then escaped=escaped+1;print('ESCAPED',e) end end end
local function Until(n,fn) for i=0,n do if fn() then return i end;if i<n then Step(1) end end end
local function Stack()
 local lines={}
 for i=2,45 do local d=debug.getinfo(i,'Sln');if not d then break end;lines[#lines+1]=(d.source or '?')..':'..d.currentline..' '..(d.name or '?') end
 return table.concat(lines,'\n')
end
local function Snapshot()
 local s,d=CB.VirtualStats(),CB.DiagnosticSnapshot()
 return {at=H.now,dataFailures=s.dataFailures,lastDataError=s.lastDataError or false,dataRefreshes=s.dataRefreshes,
  dataBinds=s.dataBinds,importFailures=s.importFailures,importPending=s.savedImport.pending,
  importCompletions=s.savedImport.completions,projectionCurrent=d.projectionCurrent,
  projectionDirty=d.projectionDirty,projectionPending=d.projectionPending,reason=d.blockedReason}
end
assert(C.setup(Nexus.StartupStatus().state=='ready','real TOC startup ready'))
CB.Show();Step(100)
assert(C.setup(Until(2000,function() return CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending
 and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil end)~=nil,'warm publication with no queued ViewRefresh'))
assert(C.setup(Nexus.Sync.IsReceiving()==false,'actual Sync reports no receiving; no receive stub'))
local baseline=CB.VirtualStats();local revisions=Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)
local schedules={};local after=Nexus.Scheduler.After
Nexus.Scheduler.After=function(key,delay,callback)
 local ok,why=after(key,delay,callback)
 if key==Nexus.ViewRefresh.Key() then local p=Nexus.Scheduler.Pending(key);schedules[#schedules+1]={at=H.now,delay=delay,due=p and p.due,origin=Stack()} end
 return ok,why
end
local rows=L.OrdinaryRows(2)
assert(C.setup(L.Copies(rows)==79 and Nexus.LoadoutEvidence.PublicOrdinaryCompleteness({echoes=rows}).complete,'real changed saved slot has complete79-copy evidence'))
H.perks.serverBuildSlots[1]={name='Natural ViewRefresh hold probe',verified=true,echoes=rows};H.Notify();A.Poll()
local put=CAT.Put;local ticket,id,puts
puts=0
CAT.Put=function(record,...)
 local ok,why,t=put(record,...)
 if record.importedSavedBuild and record.serverTitle=='Natural ViewRefresh hold probe' then puts=puts+1;ticket=t;id=record.id end
 return ok,why,t
end
CB.Hide();CB.Show()
assert(C.setup(Until(1000,function() return ticket~=nil end)~=nil and ticket.state=='pending'
 and type(ticket.completionCallback)=='function' and CB.VirtualStats().savedImport.pending and puts==1,'actual import owns one pending catalog ticket with original callback'))
local frame=NexusCommunityBuildsFrame;local setText=frame._classDropBtn.SetText
local faults={};local firstMessage='Synthetic callback host failure';local latestMessage='Synthetic later scheduled host failure'
frame._classDropBtn.SetText=function(self,text)
 if ticket.committed then
  local stack=Stack();local callback=stack:find('core/CommunityController.lua',1,true) and stack:find('core/BuildCatalog.lua',1,true)
  local message=callback and firstMessage or latestMessage
  faults[#faults+1]={at=H.now,stack=stack,callback=not not callback,scheduled=not not(stack:find('core/ViewRefresh.lua',1,true) and stack:find('core/Scheduler.lua',1,true)),message=message,before=Snapshot()}
  error(message,0)
 end
 return setText(self,text)
end
assert(C.setup(Until(2000,function() return #faults>0 end)~=nil and ticket.committed and faults[1].callback,
 'real catalog completion reaches the first delegated host fault'))
local first=Snapshot();local firstAt=faults[1].at
assert(C.setup(first.dataFailures==baseline.dataFailures+1 and first.lastDataError==firstMessage,
 'callback fault is retained by the real view ledger before observation'))
local observations={first}
for _=1,40 do Step(1);observations[#observations+1]=Snapshot() end
local held=Snapshot();local scheduledInside=false
for _,f in ipairs(faults) do if f.scheduled and f.at-firstAt<.5 then scheduledInside=true end end
C.expect(#faults==1,'no automatic refresh throws inside the retained first400ms hold',#faults)
C.expect(not scheduledInside,'natural revision scheduler respects the callback view-failure deadline')
C.guard(Nexus.Revisions.Get(Nexus.Revisions.BUILD_LIBRARY_CHANGED)>revisions and #schedules>0 and CAT.Get(id)~=nil,
 'real catalog commit publishes revision and naturally schedules ViewRefresh')
C.guard(held.dataRefreshes==first.dataRefreshes and held.dataFailures==first.dataFailures and held.lastDataError==firstMessage,
 'old dataRefreshes/count checks remain unchanged during observed exceptions')
local history=Nexus.Errors.History()
print('FAULT_TIMELINE',F.Serialize({firstAt=firstAt,faults=faults,schedules=schedules,first=first,held=held,observations=observations,errorHistory=history}))
frame._classDropBtn.SetText=setText;CAT.Put=put;Nexus.Scheduler.After=after
local restoredAt=H.now;local beforePumps=Nexus.ViewProjections.WorkStats().communityPumps
local recovered=Until(2000,function() return CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending and CB.VirtualStats().lastDataError==nil end)
local final=Snapshot();local finalImport=CB.VirtualStats().savedImport
C.guard(recovered and final.at-firstAt>=.5 and Nexus.ViewProjections.WorkStats().communityPumps>beforePumps,
 'restored host recovers through positive real projection work after500ms',recovered)
C.guard(finalImport.completions==baseline.savedImport.completions+1 and finalImport.writes==baseline.savedImport.writes+1 and puts==1,
 'original real import completes exactly once despite display failures')
C.guard(escaped==0 and #H.actions==0 and #H.sent==0,'no frame escape, synthetic game action or network send')
print('RECOVERY',F.Serialize({restoredAt=restoredAt,firstFaultAt=firstAt,recoveredFrames=recovered,final=final,import=finalImport,positivePumps=Nexus.ViewProjections.WorkStats().communityPumps-beforePumps,escaped=escaped,actions=#H.actions,sent=#H.sent}))
end)

for _,faulted in ipairs({false,true}) do
C.scenario(faulted and 'share-before-library-host-failure' or 'share-before-library-healthy',function()
-- Evidence-only actual Share-before-Library path. Frozen source is not edited.
local S=dofile('tests/prototype/share_test_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local H,CAT=S.Boot()
local CB=Nexus.CommunityBuilds
local function LibraryExists()
 for _,f in ipairs(H.frames) do if f:GetName()=='NexusCommunityBuildsFrame' then return true end end
 return false
end
print('SHARE_BOOT_ISOLATION',F.Serialize({namedGlobalExists=NexusCommunityBuildsFrame~=nil,activeLibraryFrameExists=LibraryExists()}))
local function Upvalue(fn,wanted)
 if type(fn)~='function' then return end
 for i=1,60 do
  local name,value=debug.getupvalue(fn,i)
  if not name then return end
  if name==wanted then return value end
 end
end
local function Renderer()
 local instance=Upvalue(CB.ShowPostBuild,'RendererInstance')
 return Upvalue(Upvalue(instance,'EnsureCommunityRenderer'),'communityRenderer')
end
local function Stack(expectedCallback)
 local rows,controller,lifecycle,catalog={},nil,false,false
 for i=2,50 do
  local info=debug.getinfo(i,'Slnf')
  if not info then break end
  rows[#rows+1]=(info.source or '?')..':'..tostring(info.currentline)..' ('..(info.name or '?')..')'
  if not controller and info.source=='@core/CommunityController.lua' then controller=info.func end
  if info.source=='@core/MainLifecycle.lua' then lifecycle=true end
  if info.source=='@core/BuildCatalog.lua' then catalog=true end
 end
 return table.concat(rows,'\n'),controller~=nil and controller==expectedCallback and catalog,lifecycle,catalog
end
assert(C.setup(Nexus.StartupStatus().state=='ready' and CAT.ManualPreparationStatus().ready,
 'real TOC, Store and catalog preparation are ready'))
assert(C.setup(NEXUS_TEST_NO_PROFILE_CLOCK~=true and type(debugprofilestop)=='function'
 and GetTime()==H.now,'unchanged default harness clock and profiler pacing'))
assert(C.setup(not LibraryExists() and Renderer()
,'Library frame never constructed before actual Share'))
local originalSlots=H.Clone(H.perks.serverBuildSlots)
local beforeCatalog=CAT.DebugStats()
local realPut=CAT.Put
local ticket,id,puts,putStack
puts=0
CAT.Put=function(record,...)
 local ok,why,receipt=realPut(record,...)
 if record and record.title=='INDEPENDENT-SHARE-BEFORE-LIBRARY' then
  puts=puts+1;ticket=receipt;id=record.id;putStack=Stack()
  print('REAL_PUT',F.Serialize({ok=ok,why=why,id=id,state=receipt and receipt.state,at=H.now}))
 end
 return ok,why,receipt
end
local realPending=CB.PumpPendingShare
local pumps,pendingPumps,lastPending,lastSubmitted=0,0,nil,nil
CB.PumpPendingShare=function(...)
 local pending,submitted=realPending(...)
 pumps=pumps+1;if pending then pendingPumps=pendingPumps+1 end
 lastPending,lastSubmitted=pending,submitted
 return pending,submitted
end
local outcome,popup=S.Post('INDEPENDENT-SHARE-BEFORE-LIBRARY')
assert(C.setup(ticket and ticket.state=='pending' and type(ticket.completionCallback)=='function'
 and puts==1 and outcome.localPending and outcome.localStage=='saving'
 and not outcome.localSaved and not popup:IsShown(),
 'actual enabled Share button produces exactly one real pending Put ticket and closes the form'))
CB.ShowPostBuild()
assert(C.setup(popup:IsShown() and popup._shareStatus and not LibraryExists()
,
 'public Share reopen precedes Library and exposes existing status host method'))
local originalText=popup._shareStatus.SetText
local callbackCalls,throws,callbackStack,callbackLifecycle,callbackCatalog=0,0,nil,false,false
local expectedCompletionCallback=ticket.completionCallback
local message='Synthetic Share status SetText fault before Library initialization'
popup._shareStatus.SetText=function(self,...)
 local trace,isCallback,isLifecycle,isCatalog=Stack(expectedCompletionCallback)
 if isCallback then
  callbackCalls=callbackCalls+1;callbackStack=trace
  callbackLifecycle,callbackCatalog=isLifecycle,isCatalog
  if faulted and throws==0 then
   throws=throws+1
   popup._shareStatus.SetText=originalText -- one host fault; all later work is healthy
   error(message,0)
  end
 end
 return originalText(self,...)
end
local start=H.now
local commitFrame,escaped= nil,0
for i=1,400 do
 local ok,why=pcall(H.Advance,.05,.05)
 if not ok then escaped=escaped+1;print('ESCAPED',tostring(why)) end
 if not commitFrame and ticket.state~='pending' then
  commitFrame=i
  print('COMMIT_OBSERVATION',F.Serialize({at=H.now,frame=i,ticketState=ticket.state,
   committed=ticket.committed,status=CB.ShareStatus(id),startup=Nexus.StartupStatus(),
   mutationCompletionFailures=CAT.DebugStats().mutationCompletionFailures,
   callbackCalls=callbackCalls,throws=throws,lastPending=lastPending,lastSubmitted=lastSubmitted}))
 end
end
popup._shareStatus.SetText=originalText
CAT.Put=realPut;CB.PumpPendingShare=realPending
local final,stats,startup=CB.ShareStatus(id),CAT.DebugStats(),Nexus.StartupStatus()
local record=CAT.Get(id)
assert(C.setup(commitFrame and ticket.state=='committed' and ticket.committed==true
 and ticket.completionCallback==nil and record and record.title=='INDEPENDENT-SHARE-BEFORE-LIBRARY',
 'registered lifecycle really commits the Share record and consumes its original ticket callback'))
assert(C.setup(callbackCalls==1 and callbackLifecycle and callbackCatalog and callbackStack,
 'status SetText is reached from actual controller completion, BuildCatalog and MainLifecycle stack'))
assert(C.setup(throws==(faulted and 1 or 0),'only selected fault arm injects one actual host exception'))
C.guard(not LibraryExists(),
 'neither arm constructs Library to settle Share')
C.guard(puts==1 and H.putCalls[id]==1 and escaped==0,
 'one real submission, no retry and no exception escaping ordinary lifecycle')
C.guard(S.T.Equal(originalSlots,H.perks.serverBuildSlots) and #H.actions==0,
 'server-source snapshots and gameplay action count remain unchanged')
C.guard(pumps>0 and H.now-start>=19.99 and H.now-start<20.01,
 'real lifecycle pumps the public pending-Share operation throughout bounded default-clock observation')
C.expect(final.localSaved==true and final.localPending==false and final.localStage=='saved',
 'committed Share completion settles its truthful public status',F.Serialize(final))
C.expect(lastPending==false and startup.syncGate=='open',
 'ordinary lifecycle releases pending Share and opens Sync gate after committed save',F.Serialize(startup))
C.expect(stats.mutationCompletionFailures==beforeCatalog.mutationCompletionFailures,
 'display fault does not abort actual catalog completion callback',F.Serialize(stats))
print('FINAL_OBSERVATION',F.Serialize({faulted=faulted,seconds=H.now-start,commitFrame=commitFrame,
 id=id,ticketState=ticket.state,ticketPumps=ticket.pumps,puts=puts,callbackCalls=callbackCalls,
 throws=throws,mutationCompletionFailures=stats.mutationCompletionFailures,
 status=final,startup=startup,shareText=popup._shareStatus:GetText(),pumps=pumps,pendingPumps=pendingPumps,
 lastPending=lastPending,lastSubmitted=lastSubmitted,actions=#H.actions,
 syntheticSent=#H.sent,broadcastCalls=#H.shareCalls,escaped=escaped,
 libraryFrameAbsent=not LibraryExists(),defaultProfilerClock=type(debugprofilestop)=='function'}))
print('CALLBACK_STACK_BEGIN\n'..tostring(callbackStack)..'\nCALLBACK_STACK_END')
print('PUT_STACK_BEGIN\n'..tostring(putStack)..'\nPUT_STACK_END')
end)
end


C.scenario('direct-show-host-exception-held',function()
 local H,CB=Boot({value=true},true)
 Step(H,100)
 local message='Synthetic direct Show host exception'
 local marker=setmetatable({},{__tostring=function() return message end})
 local create=CreateFrame;local setter;local times={}
 CreateFrame=function(kind,name,...)
  local f=create(kind,name,...)
  if name=='NexusCommunityBuildsFrame' then
   local show=f.Show
   f.Show=function(self,...)
    if not setter and self._classDropBtn then
     setter=self._classDropBtn.SetText
     self._classDropBtn.SetText=function() times[#times+1]=H.now;error(marker,0) end
    end
    return show(self,...)
   end
  end
  return f
 end
 local ok,err=pcall(CB.Show);CreateFrame=create
 if not C.setup(#times==1 and setter and CB.IsShown()
  and type(NexusCommunityBuildsFrame:GetScript('OnUpdate'))=='function',
  'actual Show reaches one host fault with real frame pump attached') then return end
 C.guard(not ok and err==marker,'public Show propagates the exact original exception value')
 local first=CB.VirtualStats()
 C.expect(first.dataFailures==1 and first.lastDataError==message,
  'thrown Show records its view failure before returning the exception')
 local escaped=Step(H,40)
 C.expect(#times==1,'direct Show failure prevents actual host retry for first400ms',#times)
 NexusCommunityBuildsFrame._classDropBtn.SetText=setter
 Nexus.Sync.IsReceiving=function() return false end
 local recovered=Settle(H,CB,2000)
 C.guard(recovered and H.now-times[1]>=.5 and CB.VirtualStats().lastDataError==nil
  and CB.DiagnosticSnapshot().projectionCurrent,'restored Show dependency automatically recovers after hold',recovered)
 C.guard(escaped==0 and #H.actions==0 and #H.sent==0,'Show fault recovery has no frame escape or game/network action')
 print('OBSERVED direct-Show-fault-times',F.Serialize(times))
end)


for _,faulted in ipairs({false,true}) do
 local rawprint=print;local messages={}
 print=function(...)
  local row={};for i=1,select('#',...) do row[i]=tostring(select(i,...)) end
  messages[#messages+1]=table.concat(row,' ');return rawprint(...)
 end
 C.scenario(faulted and 'detail-publish-view-failure' or 'detail-publish-healthy',function()
  local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
  local H=F.Boot(F.Database(),function(h) h.playerLevel=60;h.perks.serverActiveSlot=1
   h.perks.serverBuildSlots={[1]={name='Actual detail publication',verified=true,echoes=L.OrdinaryRows(3)}} end)
  local CB,CAT=Nexus.CommunityBuilds,Nexus.BuildCatalog
  CB.Show();local mirror
  for _=1,2500 do
   H.Advance(.01,.01)
   if CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending then
    for _,b in pairs(CB.Builds()) do if b.importedSavedBuild and b.serverSlot==1 then mirror=b end end
    if mirror and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil then break end
   end
  end
  if not C.setup(mirror and CAT.Get(mirror.id),'actual saved mirror settles before detail publication') then return end
  H.Advance(10,.01)
  CB.Select(mirror.id);local detail
  for _,f in ipairs(H.frames) do if f.shareBtn and f.shareBtn.GetText then detail=f end end
  if not C.setup(detail and detail:IsShown() and detail.shareBtn:IsShown()
   and detail.shareBtn:GetText()=='Share Build...','real own saved-mirror detail Share Build... action is visible') then return end
  -- PR135: Copy into Editor is draft-only; the own saved mirror shares only
  -- through its separate Share Build... action and the actual confirmation.
  local copyShown=detail.lockBtn~=nil and detail.lockBtn:IsShown()
   or #V.Frames(H,function(f) return f:GetParent()==detail and f:IsShown()
    and V.Plain(f:GetText())=='Copy into Editor' end)>0
  C.guard(not copyShown,'own saved mirror hides the draft-only Copy action')
  local commit=CAT.CommitMaintenance;local tickets={}
  CAT.CommitMaintenance=function(...)
   local ok,why,ticket=commit(...);if type(ticket)=='table' then tickets[#tickets+1]=ticket end
   return ok,why,ticket
  end
  local frame=NexusCommunityBuildsFrame;local setText=frame._classDropBtn.SetText;local faults={}
  if faulted then frame._classDropBtn.SetText=function()
   faults[#faults+1]={at=H.now,stack=debug.traceback('',2)};error('DETAIL_FINISH_VIEW_HOST_FAULT',0)
  end end
  local prior=CAT.Get(mirror.id);local priorPublished=prior and prior.publishedBuildId
  local priorPopup,actionsBefore,sentBefore=H.popup,#H.actions,#H.sent
  local opened,openErr=pcall(function() detail.shareBtn:Click() end)
  local popup=H.popup
  if not C.setup(opened and popup~=nil and popup~=priorPopup and popup.which=='NEXUS_SHARE_SAVED_BUILD'
   and type(popup.data)=='table' and popup.data.id==mirror.id,
   'real detail Share click opens its actual NEXUS_SHARE_SAVED_BUILD confirmation',openErr) then return end
  local unconfirmed=CAT.Get(mirror.id)
  if not C.guard(#tickets==0 and unconfirmed and unconfirmed.publishedBuildId==priorPublished
   and detail.shareBtn:GetText()=='Share Build...' and #H.actions==actionsBefore and #H.sent==sentBefore,
   'open Share confirmation creates no commit ticket, publication or send before Accept',#tickets) then return end
  local accepted,err=pcall(H.AcceptPopup)
  if not C.setup(accepted and #tickets==1 and tickets[1].state=='pending'
   and detail.shareBtn:GetText()=='Sharing...','real detail Share confirmation queues one asynchronous publish ticket',err) then return end
  local escaped=0
  for _=1,1200 do if tickets[1].state~='pending' then break end;escaped=escaped+Step(H,1) end
  local source=CAT.Get(mirror.id);local published=source and source.publishedBuildId and CAT.Get(source.publishedBuildId)
  local terminalOk,terminalId=CB.PublishImportedBuild(mirror.id)
  C.guard(tickets[1].committed and published and terminalOk==true and terminalId==published.id,
   'actual catalog publication and terminal receipt are successful')
  local wrong=0
  for _,line in ipairs(messages) do if line:find('Catalog completion failed:',1,true) then wrong=wrong+1 end end
  C.expect(wrong==0,'display failure never reports a successful detail publication as failed catalog completion',wrong)
  C.expect(#faults==(faulted and 1 or 0),'detail Finish honors the first actual callback view-failure hold',#faults)
  if faulted then C.guard(CB.VirtualStats().dataFailures==1 and CB.VirtualStats().lastDataError=='DETAIL_FINISH_VIEW_HOST_FAULT',
   'real publication display fault remains classified in view ledger') end
  frame._classDropBtn.SetText=setText;CAT.CommitMaintenance=commit
  C.guard(Settle(H,CB,2000)~=nil and escaped==0 and #H.actions==0,
   'detail publication recovers without frame escape or gameplay action')
  print('OBSERVED detail-publish-faults',faulted,F.Serialize({faults=faults,wrongCatalogMessages=wrong,terminalOk=terminalOk,terminalId=terminalId,syntheticSent=#H.sent}))
 end)
 print=rawprint
end


-- Popup-only poll and healthy completion status preserve their own UI lifetime.
-- The stale text below is a synthetic host-state fault, not a catalog mutation.
for _,withLibrary in ipairs({false,true}) do
C.scenario(withLibrary and 'popup-scope-poll-hide' or 'popup-scope-poll-before-library',function()
 local S=dofile('tests/prototype/share_test_support.lua')
 local H,CAT=S.Boot();local CB=Nexus.CommunityBuilds
 local function Library()
  for _,f in ipairs(H.frames) do if f:GetName()=='NexusCommunityBuildsFrame' then return f end end
 end
 if withLibrary then CB.Show();S.T.Until(H,function() return CB.DiagnosticSnapshot().projectionCurrent
  and not CB.VirtualStats().savedImport.pending end) end
 local outcome,popup=S.Post('PERSISTENT-POPUP-STATUS-HOLD');local id=outcome.id
 CB.ShowPostBuild()
 S.T.Until(H,function() return CB.ShareStatus(id).localSaved==true and not CB.ShareStatus(id).localPending end)
 H.Advance(.6,.05)
 local status=popup._shareStatus;local setter=status.SetText;local correctText=status:GetText()
 local poll=popup:GetScript('OnUpdate');local calls,escaped={},0
 C.setup(popup:IsShown() and type(poll)=='function' and H.putCalls[id]==1 and CAT.Get(id)
  and ((Library()~=nil)==withLibrary),'actual Share settles once before synthetic popup-only display fault')
 setter(status,'Synthetic stale status text')
 status.SetText=function()
  local fromPoll=false
  for i=2,50 do local info=debug.getinfo(i,'f');if not info then break end;if info.func==poll then fromPoll=true end end
  calls[#calls+1]={at=H.now,poll=fromPoll};error('Persistent popup status host failure',0)
 end
 local function Advance(n)
  for _=1,n do if not pcall(H.Advance,.05,.05) then escaped=escaped+1 end end
 end
 for _=1,20 do if #calls>0 then break end;Advance(1) end
 if not C.setup(#calls==1 and calls[1].poll,'real popup OnUpdate reaches the first persistent host exception') then status.SetText=setter;return end
 local firstAt=calls[1].at
 if withLibrary then
  -- Hide inside the second actual hold: its 1s deadline outlasts one popup tick.
  for _=1,20 do if #calls>=2 then break end;Advance(1) end
  CB.Hide()
 end
 local before=CB.VirtualStats();local pumps=Nexus.ViewProjections.WorkStats().communityPumps
 Advance(64)
 local deltas,bounds,held={}, {},true
 for i=2,#calls do
  deltas[#deltas+1]=calls[i].at-calls[i-1].at;bounds[#bounds+1]=math.min(.5*2^math.min(i-2,4),8)
  if deltas[#deltas]+.0000001<bounds[#bounds] then held=false end
 end
 C.guard(#calls>=3 and calls[2].poll,'persistent fault positively reaches later real popup polls')
 C.expect(held,'every actual popup retry respects the failure-to-failure deadline including public Library Hide',F.Serialize(deltas))
 C.expect(escaped==0,'popup-only status errors stay contained inside ordinary updates',escaped)
 C.expect(CB.VirtualStats().statusFailures==#calls and CB.VirtualStats().lastStatusError=='Persistent popup status host failure',
  'each actual popup exception is retained once in its independent status ledger',CB.VirtualStats().statusFailures)
 C.guard(CB.VirtualStats().dataFailures==0 and CB.VirtualStats().lastDataError==nil,
  'popup-only faults leave the unrelated main-view failure ledger untouched')
 C.guard((not withLibrary and not Library()) or (withLibrary and not CB.IsShown()
  and Library():GetScript('OnUpdate')==nil),'popup polling neither constructs nor resumes the dormant main Library')
 C.guard(Nexus.ViewProjections.WorkStats().communityPumps==pumps and CB.VirtualStats().savedImport.pumps==before.savedImport.pumps,
  'held popup-only polls perform no hidden Library projection or import work')
 status.SetText=setter
 Advance(70)
 local _,currentSentence=CB.ShareStatusText(id)
 C.expect(type(currentSentence)=='string' and status:GetText():find(currentSentence,1,true)~=nil,
  'restored popup setter positively repairs its stale text through the real poll')
 C.guard(CB.ShareStatus(id).localSaved and not CB.ShareStatus(id).localPending and H.putCalls[id]==1 and #H.actions==0,
  'popup failures neither repeat the Share submission nor perform gameplay actions')
 print('POPUP_POLL_TIMELINE',F.Serialize({withLibrary=withLibrary,firstAt=firstAt,calls=calls,deltas=deltas,bounds=bounds,
  escaped=escaped,failures=CB.VirtualStats().statusFailures,restoredText=status:GetText(),puts=H.putCalls[id]}))
end)
end

for _,hidden in ipairs({true,false}) do
C.scenario(hidden and 'popup-scope-immediate-hidden' or 'popup-scope-immediate-held',function()
 local S=dofile('tests/prototype/share_test_support.lua')
 local H,CAT=S.Boot();local CB=Nexus.CommunityBuilds
 CB.Show();S.T.Until(H,function() return CB.DiagnosticSnapshot().projectionCurrent
  and not CB.VirtualStats().savedImport.pending and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil end)
 local frame=NexusCommunityBuildsFrame;local classSet=frame._classDropBtn.SetText
 local outcome,popup=S.Post(hidden and 'IMMEDIATE-HIDDEN-STATUS' or 'IMMEDIATE-HELD-STATUS');local id=outcome.id
 CB.ShowPostBuild();if hidden then CB.Hide() end
 local function InCompletion()
  for i=2,50 do local info=debug.getinfo(i,'S');if not info then break end
   if info.source=='@core/CommunityController.lua' then return true end
  end
  return false
 end
 local firstFault,mainFaults=nil,0
 if not hidden then frame._classDropBtn.SetText=function(self,...)
  if InCompletion() and mainFaults==0 then
   mainFaults=1;firstFault=H.now;frame._classDropBtn.SetText=classSet;error('Main view fails while Share status stays healthy',0)
  end
  return classSet(self,...)
 end end
 local setter=popup._shareStatus.SetText;local immediate={}
 popup._shareStatus.SetText=function(self,text)
  local s=CB.ShareStatus(id)
  if InCompletion() and s and s.localSaved and not s.localPending then
   local _,sentence=CB.ShareStatusText(id)
   immediate[#immediate+1]={at=H.now,text=text,sentence=sentence,viewError=CB.DiagnosticSnapshot().blockedReason=='projection-error',mainHidden=not CB.IsShown()}
  end
  return setter(self,text)
 end
 S.T.Until(H,function() return CB.ShareStatus(id).localSaved and not CB.ShareStatus(id).localPending end)
 C.setup(CAT.Get(id) and H.putCalls[id]==1 and popup:IsShown(),'real pending Share commits once while its form remains open')
 C.setup(hidden or (mainFaults==1 and firstFault~=nil and CB.VirtualStats().dataFailures==1),
  'held arm reaches one actual main-view callback failure before settled status notification')
 C.expect(#immediate>0,'healthy status reaches its actual settled controller callback immediately despite hidden or held Library',#immediate)
 if not hidden then C.expect(#immediate>0 and immediate[1].viewError and immediate[1].at-firstFault<.5,
  'healthy Share text updates inside the main-view failure hold rather than waiting for its poll') end
 C.expect(#immediate>0 and type(immediate[1].sentence)=='string'
  and immediate[1].text:find(immediate[1].sentence,1,true)~=nil,
  'actual Share status text reflects the committed result at its synchronous completion notification')
 C.guard(hidden and not CB.IsShown() and frame:GetScript('OnUpdate')==nil or not hidden and CB.IsShown(),
  'Share status completion preserves the requested Library visibility and frame lifetime')
 C.guard(CAT.DebugStats().mutationCompletionFailures==0 and #H.actions==0 and H.putCalls[id]==1,
  'healthy status notification completes its original Share without callback failure or repeat submission')
 popup._shareStatus.SetText=setter;frame._classDropBtn.SetText=classSet
 print('POPUP_IMMEDIATE',F.Serialize({hidden=hidden,firstFault=firstFault,mainFaults=mainFaults,immediate=immediate,
  text=popup._shareStatus:GetText(),status=CB.ShareStatus(id)}))
end)
end


-- Status-ledger probes use1075676 as the staged baseline. Jobs are read-only
-- test witnesses; production uses the real RequestBuilds result.
for _,finding in ipairs({'popup','history','pending'}) do
for _,faulted in ipairs({false,true}) do
C.scenario('responsible-ledger-'..finding..(faulted and '-fault' or '-healthy'),function()
-- Independent probes of three renderer ledger findings. Real TOC/public paths.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local H=F.Boot(F.Database(),function(h)
 h.playerLevel=60;h.perks.serverBuildSlots={};h.perks.serverActiveSlot=1
end)
local CB,CAT,VP=Nexus.CommunityBuilds,Nexus.BuildCatalog,Nexus.ViewProjections
local escaped=0
local function Step(n)
 for _=1,n do
  local ok,err=pcall(H.Advance,.01,.01)
  if not ok then escaped=escaped+1;print('ESCAPED',tostring(err)) end
 end
end
local function Until(limit,fn)
 for i=0,limit do if fn() then return i end;if i<limit then Step(1) end end
end
local function Snapshot()
 local s,d=CB.VirtualStats(),CB.DiagnosticSnapshot()
 return {at=H.now,dataFailures=s.dataFailures,lastDataError=s.lastDataError or false,
  dataBinds=s.dataBinds,dataRefreshes=s.dataRefreshes,importFailures=s.importFailures,
  importPending=s.savedImport.pending,importCompletions=s.savedImport.completions,
  projectionCurrent=d.projectionCurrent,projectionPending=d.projectionPending,
  projectionDirty=d.projectionDirty,reason=d.blockedReason,scope=d.filterScope,
  pumps=VP.WorkStats().communityPumps,publications=VP.WorkStats().publications,
  history=Nexus.Errors.History(),sessionErrors=Nexus.Errors.SessionCount()}
end
local function Upvalue(fn,wanted)
 for i=1,60 do local k,v=debug.getupvalue(fn,i);if not k then return end;if k==wanted then return v end end
end
local function Stack(expectedCallback)
 local rows,controller,lifecycle,catalog={},nil,false,false
 for i=2,50 do
  local d=debug.getinfo(i,'Slnf');if not d then break end
  rows[#rows+1]=(d.source or '?')..':'..d.currentline..' '..(d.name or '?')
  if not controller and d.source=='@core/CommunityController.lua' then controller=d.func end
  if d.source=='@core/MainLifecycle.lua' then lifecycle=true end
  if d.source=='@core/BuildCatalog.lua' then catalog=true end
 end
 return table.concat(rows,'\n'),controller~=nil and controller==expectedCallback and catalog,lifecycle,catalog
end
local function Matches(message)
 local n=0
 for _,r in ipairs(Nexus.Errors.History()) do if r.message==message then n=n+1 end end
 return n
end
assert(C.setup(Nexus.StartupStatus().state=='ready' and type(debugprofilestop)=='function'
 and NEXUS_TEST_NO_PROFILE_CLOCK~=true,'real startup and unmodified default profiler clock'))
CB.Show();Step(100)
assert(C.setup(Until(2000,function()
 return CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending
  and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil and CAT.RootState().candidate~=true
end)~=nil,'healthy real Library view/import/catalog and revision scheduler settle'))
assert(C.setup(CB.DiagnosticSnapshot().filterScope=='all' and Nexus.Sync.IsReceiving()==false,
 'actual All scope and no receive window without replacing Sync'))

if finding=='popup' then
 CB.ShowPostBuild();local popup=assert(NexusPostPopup)
 local status=popup._shareStatus;local original=status.SetText;local poll=popup:GetScript('OnUpdate')
 assert(C.setup(popup:IsShown() and CB.IsShown() and type(poll)=='function',
  'public Share form and healthy Library are simultaneously open'))
 local before=Snapshot();local observations,throws={},0
 original(status,'Synthetic stale popup text')
 status.SetText=function(self,...)
  local inPoll=false
  for i=2,50 do local d=debug.getinfo(i,'f');if not d then break end;if d.func==poll then inPoll=true end end
  observations[#observations+1]={at=H.now,inPoll=inPoll,stack=Stack()}
  if faulted and throws==0 then
   throws=1;status.SetText=original
   error('Independent popup-only label fault',0)
  end
  return original(self,...)
 end
 assert(C.setup(Until(100,function() return #observations>0 end)~=nil and observations[1].inPoll
  and throws==(faulted and 1 or 0),'real popup OnUpdate reaches matched healthy/fault SetText seam'))
 status.SetText=original
 local first=Snapshot()
 if faulted then
  C.expect(CB.VirtualStats().statusFailures==1 and CB.VirtualStats().lastStatusError=='Independent popup-only label fault'
   and CB.DiagnosticSnapshot().shareStatusError==true,'status fault owns an independent bounded counter message and diagnostic')
 else
  C.expect(CB.VirtualStats().statusFailures==0 and CB.VirtualStats().lastStatusError==nil
   and CB.DiagnosticSnapshot().shareStatusError==false,'healthy popup text work leaves its status ledger clear')
 end
 C.expect(first.dataFailures==before.dataFailures and first.lastDataError==before.lastDataError,
  'popup-only label failure does not charge the Library projection ledger',F.Serialize(first))
 C.expect(first.projectionCurrent and first.reason=='none',
  'healthy Library remains current after isolated popup text work',F.Serialize(first))
 local revision=Nexus.Revisions.Get(Nexus.Revisions.DPS_CHANGED)
 Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{scope='all',reason='independent popup-ledger probe'})
 assert(C.setup(Nexus.Revisions.Get(Nexus.Revisions.DPS_CHANGED)>revision
  and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())~=nil,'real DPS revision naturally schedules ViewRefresh'))
 Step(40);local held=Snapshot()
 if faulted then
  C.expect(CB.VirtualStats().lastStatusError=='Independent popup-only label fault' and CB.DiagnosticSnapshot().shareStatusError,
   'All publication during the status hold preserves independent status error evidence')
 else
  C.expect(CB.VirtualStats().statusFailures==0 and CB.VirtualStats().lastStatusError==nil
   and CB.DiagnosticSnapshot().shareStatusError==false,'healthy All publication creates no status error evidence')
 end
 C.expect(held.pumps>first.pumps,'independent healthy All projection work advances within400ms after revision',F.Serialize(held))
 local recovered=Until(2000,function() return CB.DiagnosticSnapshot().projectionCurrent and CB.VirtualStats().lastDataError==nil end)
 C.guard(recovered~=nil and VP.WorkStats().communityPumps>first.pumps,'eventual restored status permits positive projection work and publication',recovered)
 C.guard(throws==(faulted and 1 or 0) and escaped==0 and #H.actions==0 and #H.sent==0,
  'one selected host exception, no gameplay/network actions or escaping frame error')
 Step(100)
 C.expect(CB.VirtualStats().lastStatusError==nil and CB.DiagnosticSnapshot().shareStatusError==false,
  'a successful real status retry clears only its status error evidence')
 print('POPUP_LEDGER',F.Serialize({faulted=faulted,before=before,first=first,held400ms=held,final=Snapshot(),
  observations=observations,throws=throws,recoveryFramesAfter400ms=recovered}))
elseif finding=='history' then
 local before=Snapshot();local beforeCatalog=CAT.DebugStats();local title='Independent history callback saved slot'
 local rows=L.OrdinaryRows(2)
 assert(C.setup(L.Copies(rows)==79 and Nexus.LoadoutEvidence.PublicOrdinaryCompleteness({echoes=rows}).complete,
  'changed saved slot has complete ordinary79-copy payload'))
 H.perks.serverBuildSlots[1]={name=title,verified=true,echoes=rows};H.Notify();Nexus.GameAdapter.Poll()
 local realPut=CAT.Put;local ticket,id,puts=nil,nil,0
 CAT.Put=function(record,...)
  local ok,why,t=realPut(record,...)
  if record.importedSavedBuild and record.serverTitle==title then puts=puts+1;ticket=t;id=record.id end
  return ok,why,t
 end
 CB.Hide();CB.Show()
 assert(C.setup(Until(1000,function() return ticket~=nil end)~=nil and ticket.state=='pending'
  and type(ticket.completionCallback)=='function' and CB.VirtualStats().savedImport.pending and puts==1,
  'actual public Show import submits one real pending catalog ticket'))
 local label=NexusCommunityBuildsFrame._classDropBtn;local original=label.SetText
 local calls,throws,callbackStack,origin=0,0,nil,false
 local expectedCompletionCallback=ticket.completionCallback
 local message='Independent controller-only retained evidence fault'
 label.SetText=function(self,...)
  local trace,callback,lifecycle,catalog=Stack(expectedCompletionCallback)
  if callback then
   calls=calls+1;callbackStack=trace;origin=lifecycle and catalog
   if faulted and throws==0 then throws=1;label.SetText=original;error(message,0) end
  end
  return original(self,...)
 end
 assert(C.setup(Until(2000,function() return calls>0 end)~=nil and origin and ticket.committed,
  'real catalog/MainLifecycle completion invokes delegated class-label host seam'))
 label.SetText=original;CAT.Put=realPut
 local caught=Snapshot();local matchesCaught=Matches(message)
 assert(C.setup(throws==(faulted and 1 or 0) and (not faulted or caught.lastDataError==message),
  'selected actual callback exception is contained and visible in volatile diagnostic'))
 C.expect(matchesCaught==(faulted and 1 or 0),
  'contained callback exception is retained once in Errors ring at observation',matchesCaught)
 local recovered=Until(2000,function() return CB.DiagnosticSnapshot().projectionCurrent
  and CB.VirtualStats().lastDataError==nil and not CB.VirtualStats().savedImport.pending end)
 local after=Snapshot();local matchesAfter=Matches(message)
 C.guard(recovered~=nil and after.dataBinds>before.dataBinds and after.pumps>before.pumps,
  'real healthy publication recovers and clears volatile lastDataError',recovered)
 C.expect(matchesAfter==(faulted and 1 or 0),
  'original contained callback evidence survives successful publication in Errors history',matchesAfter)
 C.guard(CAT.Get(id) and ticket.committed and puts==1 and CAT.DebugStats().mutationCompletionFailures==beforeCatalog.mutationCompletionFailures,
  'original real ticket commits without repeat submission or callback failure')
 C.guard(escaped==0 and #H.actions==0 and #H.sent==0,'no frame escape or gameplay/network action')
 print('CONTROLLER_HISTORY',F.Serialize({faulted=faulted,before=before,caught=caught,after=after,
  matchesCaught=matchesCaught,matchesAfter=matchesAfter,throws=throws,calls=calls,callbackStack=callbackStack,
  recoveredFrames=recovered,ticketState=ticket.state,puts=puts}))
elseif finding=='pending' then
 local jobs=Upvalue(VP.RequestBuilds,'jobs')
 assert(C.setup(type(jobs)=='table' and jobs.builds==nil,'production jobs table is read-only witnessed with no active warm job'))
 local frame=NexusCommunityBuildsFrame;local label=frame._resultText;local original=label.SetText
 local before=Snapshot();local calls,throws,atBindJob,bindStack=0,0,nil,nil
 local message='Independent pending-label bind fault'
 label.SetText=function(self,text,...)
  if tostring(text):find('Updating results...',1,true) then
   calls=calls+1;atBindJob=jobs.builds;bindStack=Stack()
   if faulted and throws==0 then throws=1;label.SetText=original;error(message,0) end
  end
  return original(self,text,...)
 end
 local ok,err=pcall(function() frame._classDropBtn:Click() end)
 label.SetText=original
 local retained=jobs.builds;local immediate=Snapshot()
 assert(C.setup(calls==1 and type(atBindJob)=='table' and retained==atBindJob,
  'actual class-filter click requests a real retained job before pending-label binding'))
 assert(C.setup(faulted and not ok and err==message and throws==1 or not faulted and ok and throws==0,
  'matched actual UI bind preserves expected success or exact thrown value'))
 C.expect(immediate.projectionPending==true,
  'diagnostic reports the production job still pending after pending-label binding',F.Serialize(immediate))
 local firstPump,jobSameAtFirstPump=nil,nil
 for i=1,2000 do
  local jobBefore=jobs.builds;local pumps=VP.WorkStats().communityPumps
  Step(1)
  if not firstPump and VP.WorkStats().communityPumps>pumps then firstPump=i;jobSameAtFirstPump=jobBefore==retained end
  if firstPump and CB.DiagnosticSnapshot().projectionCurrent then break end
 end
 C.guard(firstPump and jobSameAtFirstPump and CB.DiagnosticSnapshot().projectionCurrent,
  'real frame pump later advances the same uncancelled job and publishes',firstPump)
 C.guard(CB.VirtualStats().lastDataError==nil and VP.WorkStats().communityPumps>before.pumps,
  'restored host recovers through positive production work')
 C.guard(escaped==0 and #H.actions==0 and #H.sent==0,'no frame escape or gameplay/network action')
 print('PENDING_TRUTH',F.Serialize({faulted=faulted,before=before,immediate=immediate,final=Snapshot(),
  actualJobAtLabel=true,actualJobRetained=true,jobKey=retained.key,jobPhase=retained.phase,
  firstPositivePumpFrame=firstPump,sameJobAtFirstPump=jobSameAtFirstPump,calls=calls,throws=throws,bindStack=bindStack}))
else error('unknown finding '..tostring(finding)) end
end)
end
end

C.scenario('unprintable-controller-error-cannot-abort-completion',function()
 local H,CB=Boot({value=true});local CAT=Nexus.BuildCatalog;local put=CAT.Put;local ticket,id
 CAT.Put=function(record,...)
  local ok,why,t=put(record,...);if record.importedSavedBuild and t then ticket=t;id=record.id end;return ok,why,t
 end
 CB.Show();NexusCommunityBuildsFrame._myBuildsBtn:Click();Nexus.Sync.IsReceiving=function() return false end
 for _=1,2000 do if ticket then break end;Step(H,1) end
 if not C.setup(ticket and ticket.state=='pending','real saved import supplies pending ticket for unprintable-error case') then return end
 local marker=setmetatable({},{__tostring=function() error('Synthetic failing error formatter',0) end})
 local frame=NexusCommunityBuildsFrame;local setter=frame._classDropBtn.SetText;local calls,origin=0,false
 frame._classDropBtn.SetText=function(self,text)
  if ticket.committed then
   calls=calls+1;frame._classDropBtn.SetText=setter
   for i=2,40 do local info=debug.getinfo(i,'S');if not info then break end;if info.source=='@core/CommunityController.lua' then origin=true end end
   error(marker,0)
  end
  return setter(self,text)
 end
 for _=1,2000 do if calls>0 then break end;Step(H,1) end
 if not C.setup(calls==1 and origin and ticket.committed and CAT.Get(id),
  'actual committed-ticket controller callback throws original non-string host error') then frame._classDropBtn.SetText=setter;return end
 local failed=CB.VirtualStats()
 C.expect(CAT.DebugStats().mutationCompletionFailures==0,'throwing error formatter cannot abort remaining real catalog completion')
 C.expect(type(failed.lastDataError)=='string' and failed.lastDataError:find('unprintable',1,true),
  'non-string exception retains a bounded truthful formatting fallback')
 local recorded=0;for _,entry in ipairs(Nexus.Errors.History()) do if entry.source=='Community.ControllerRefresh'
  and entry.message:find('unprintable',1,true) then recorded=recorded+1 end end
 C.expect(recorded==1,'unprintable contained callback error records exactly one durable error')
 Step(H,2000);local final=CB.VirtualStats()
 C.expect(not final.savedImport.pending and final.savedImport.completions==1 and final.savedImport.writes==1
  and CB.DiagnosticSnapshot().projectionCurrent,'original saved import and publication settle after unprintable display fault')
 frame._classDropBtn.SetText=function() error(marker,0) end
 local ok,err=pcall(CB.Refresh);frame._classDropBtn.SetText=setter;CAT.Put=put
 C.expect(not ok and err==marker,'explicit Refresh rethrows original unprintable error value rather than formatter error')
 C.guard(#H.actions==0 and #H.sent==0,'unprintable-error containment causes no game/network actions')
 print('UNPRINTABLE_CALLBACK',F.Serialize({callbackFailures=CAT.DebugStats().mutationCompletionFailures,recorded=recorded,final=final,exactError=err==marker}))
end)


-- Explicit entry regressions use78177db as their baseline. Real admitted rows,
-- public controls and host-only faults retain matched healthy controls.
for _,action in ipairs({'show','refresh','class','search','select','page'}) do
for _,faulted in ipairs({false,true}) do
C.scenario('explicit-status-view-'..action..(faulted and '-fault' or '-healthy'),function()
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local players={}
for i=1,25 do players[i]={name='StatusEntry'..i,class='MAGE',variant=i,title='Status route build '..i} end
local fx=L.New({players=players})
local db=fx:Install(F.Database())
db.buildFilters={qualifiedOnly=false,currentClassOnly=true,scope='all',sortMode='title',page=1,search=''}
local H=F.Boot(db,function(h) h.playerLevel=60;h.perks.serverBuildSlots={} end)
local CB,VP=Nexus.CommunityBuilds,Nexus.ViewProjections
local escaped=0
local function Step(n) for _=1,n do local ok=pcall(H.Advance,.01,.01);if not ok then escaped=escaped+1 end end end
local function Until(n,fn) for i=0,n do if fn() then return i end;if i<n then Step(1) end end end
local function State()local s,d=CB.VirtualStats(),CB.DiagnosticSnapshot();return {at=H.now,current=d.projectionCurrent,pending=d.projectionPending,reason=d.blockedReason,page=d.requestedPage,publishedPage=d.publishedPage,classOnly=d.filterCurrentClassOnly,search=d.filterSearchActive,binds=s.dataBinds,failures=s.dataFailures,statusFailures=s.statusFailures,error=s.lastDataError or false,statusError=s.lastStatusError or false,pumps=VP.WorkStats().communityPumps,publications=VP.WorkStats().publications}end
assert(C.setup(Nexus.StartupStatus().state=='ready' and type(debugprofilestop)=='function','real TOC startup/default profiler'))
CB.Show();Step(100)
assert(C.setup(Until(2000,function()return CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil end)~=nil,'warm real All and import/scheduler settled'))
local frame=NexusCommunityBuildsFrame
assert(C.setup(CB.DiagnosticSnapshot().resultCount==25 and CB.DiagnosticSnapshot().pageCount==2 and frame._nextPageBtn:IsEnabled() and Nexus.BuildCatalog.Get(fx.buildOrder[1]),'25 genuinely admitted full rows enable real paging and selection'))
CB.ShowPostBuild();local popup=NexusPostPopup
assert(C.setup(popup and popup:IsShown() and CB.IsShown(),'actual public Share popup visible with healthy Library'))
local status=popup._shareStatus;local setter=status.SetText
local class=frame._classDropBtn;local classSetter=class.SetText
local statusCalls,mainCalls,throws=0,0,0
local trace
status.SetText=function(self,...)
 statusCalls=statusCalls+1;trace=debug.traceback('actual explicit status seam',2)
 if faulted then throws=throws+1;error('Independent persistent explicit status fault',0) end
 return setter(self,...)
end
class.SetText=function(self,...)mainCalls=mainCalls+1;return classSetter(self,...)end
local before=State()
local actions={
 show=function()CB.Hide();CB.Show()end,
 refresh=function()return CB.Refresh()end,
 class=function()frame._classDropBtn:Click()end,
 search=function()frame._searchBox:SetText('Status route')end,
 select=function()CB.Select(fx.buildOrder[1])end,
 page=function()frame._nextPageBtn:Click()end,
}
local ok,result,why=pcall(assert(actions[action]));local after=State()
assert(C.setup(statusCalls==1 and throws==(faulted and 1 or 0),'actual explicit caller reaches selected healthy/fault status host seam once'))
C.expect(ok,'popup-only status error does not escape healthy Library action',result)
C.expect(mainCalls>0,'healthy main render reaches its real control binding despite status error',mainCalls)
if action=='class' then C.guard(after.classOnly~=before.classOnly,'actual requested class context changed') end
if action=='search' then C.guard(after.search,'actual requested search context changed') end
if action=='page' then
 C.guard(after.page==2,'enabled actual page control requests next page')
 C.expect(after.publishedPage==2,'cached healthy page publishes requested context despite status error',after.publishedPage)
end
C.guard(after.failures==before.failures and after.error==before.error,'status fault does not charge Library failure counter or replace its error')
C.guard(after.statusFailures==before.statusFailures+(faulted and 1 or 0),'each actual explicit status host fault charges only its own ledger once')
C.guard(not faulted or after.statusError=='Independent persistent explicit status fault','explicit status fault retains its own exact bounded message')
status.SetText=setter;class.SetText=classSetter
C.guard(Until(2000,function()return CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending end)~=nil,'restored host permits eventual healthy Library current state')
C.guard(escaped==0 and #H.actions==0 and #H.sent==0,'no frame escape or synthetic game/network action')
print('EXPLICIT_STATUS',F.Serialize({action=action,faulted=faulted,before=before,after=after,final=State(),ok=ok,result=type(result)=='string' and result or false,why=why or false,statusCalls=statusCalls,mainCalls=mainCalls,throws=throws,trace=trace}))
end)
end
end


-- Same-query reopening cannot prove recovery from a failed production job.
-- Private state is observed read-only; assertions also witness actual work times.
for _,action in ipairs({'show','refresh'}) do
for _,faulted in ipairs({false,true}) do
C.scenario('pending-view-hold-'..action..(faulted and '-fault' or '-healthy'),function()
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local H=F.Boot(F.Database(),function(h)h.playerLevel=60;h.perks.serverBuildSlots={}end)
local CB,VP=Nexus.CommunityBuilds,Nexus.ViewProjections
local escaped=0
local function Step(n)for _=1,n do local ok=pcall(H.Advance,.01,.01);if not ok then escaped=escaped+1 end end end
local function Until(n,fn)for i=0,n do if fn()then return i end;if i<n then Step(1)end end end
local function Up(fn,name)for i=1,60 do local k,v=debug.getupvalue(fn,i);if not k then return end;if k==name then return v end end end
local renderer=Up(Up(Up(CB.DiagnosticSnapshot,'RendererInstance'),'EnsureCommunityRenderer'),'communityRenderer')
-- The renderer is assembled during actual startup. Upvalues are read-only witnesses.
assert(C.setup(type(renderer)=='table','real renderer instance is available for read-only state observation'))
local d=Up(renderer.DiagnosticSnapshot,'viewDiagnostic');local pump=d.pump
local jobs=Up(VP.RequestBuilds,'jobs')
local function State()local s,ds=CB.VirtualStats(),CB.DiagnosticSnapshot();return {at=H.now,pumps=VP.WorkStats().communityPumps,publications=VP.WorkStats().publications,binds=s.dataBinds,failures=s.dataFailures,error=s.lastDataError or false,current=ds.projectionCurrent,pending=ds.projectionPending,reason=ds.blockedReason,deadline=pump.failBackoffUntil,noted=pump.failuresNoted or 0,job=jobs.builds~=nil,jobKey=jobs.builds and jobs.builds.key or false,importPending=s.savedImport.pending}end
assert(C.setup(Nexus.StartupStatus().state=='ready' and type(debugprofilestop)=='function','real startup and default profiler'))
Step(100)
assert(C.setup(Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil and not Nexus.Sync.IsReceiving(),'initial hidden revision scheduler drained without receive'))
local read=Nexus.DpsCapture.CommunityEligibilityCursorNext;local reads={}
Nexus.DpsCapture.CommunityEligibilityCursorNext=function(...)
 reads[#reads+1]={at=H.now,trace=debug.traceback('real eligibility cursor',2)}
 if faulted then return false,'Independent persistent view hold reader failure' end
 return read(...)
end
CB.Show()
if faulted then assert(C.setup(Until(200,function()return CB.VirtualStats().dataFailures>0 end)~=nil,'production frame pump reaches actual eligibility failure')) end
if faulted then CB.Refresh() end -- Real explicit request after a cancelled-job failure.
local before=State();local retained=jobs.builds
assert(C.setup(type(retained)=='table' and before.pending and not before.current and before.binds==0
 and before.failures==(faulted and 1 or 0) and (not faulted or before.deadline>H.now),
 'real same-query pending job exists, with first retained deadline only in fault arm'))
local ok,result,why=pcall(function()if action=='show'then CB.Hide();return CB.Show()else return CB.Refresh()end end)
local after=State()
assert(C.setup(ok and after.pending and not after.current and after.binds==before.binds
 and after.publications==before.publications and jobs.builds==retained and after.jobKey==before.jobKey,
 'public same-query action returns genuine pending-only state and preserves actual job identity'))
C.expect(not faulted or after.deadline==before.deadline,'pending-only Hide/Show or Refresh preserves the existing failure deadline',F.Serialize({before=before.deadline,after=after.deadline}))
local firstWork,firstState
for i=1,200 do
 Step(1)
 if VP.WorkStats().communityPumps>after.pumps then firstWork=i;firstState=State();break end
end
C.guard(firstWork~=nil,'actual production projection work eventually advances',firstWork)
if faulted then
 C.expect(firstState and firstState.at+.0000001>=before.deadline,'first automatic retry does not precede retained deadline',F.Serialize(firstState))
else C.guard(firstWork and firstWork<=20,'healthy pending control advances within ordinary200ms cadence',firstWork)end
C.guard(#reads>0 and escaped==0,'actual eligibility work is observed without frame escape')
Nexus.DpsCapture.CommunityEligibilityCursorNext=read
C.guard(Until(2000,function()return CB.DiagnosticSnapshot().projectionCurrent and CB.VirtualStats().lastDataError==nil end)~=nil,'restored dependency eventually publishes healthy current view')
C.guard(#H.actions==0 and #H.sent==0,'no synthetic gameplay or network actions')
print('HIDE_HOLD',F.Serialize({action=action,faulted=faulted,before=before,after=after,firstWorkFrames=firstWork or false,firstWork=firstState or false,final=State(),reads=reads}))
end)
end
end


-- A public Sync request opens the real receive window through synthetic
-- transport. A newly failed cold render must stop work in that same callback.
for _,faulted in ipairs({false,true}) do
C.scenario(faulted and 'cold-receive-new-hold-fault' or 'cold-receive-new-hold-healthy',function()
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local H=F.Boot(F.Database(),function(h)h.playerLevel=60;h.perks.serverBuildSlots={}end)
local CB,VP=Nexus.CommunityBuilds,Nexus.ViewProjections
local escaped=0
local function Step(n)for _=1,n do local ok=pcall(H.Advance,.01,.01);if not ok then escaped=escaped+1 end end end
local function Until(n,fn)for i=0,n do if fn()then return i end;if i<n then Step(1)end end end
local function Up(fn,name)for i=1,60 do local k,v=debug.getupvalue(fn,i);if not k then return end;if k==name then return v end end end
local renderer=Up(Up(Up(CB.DiagnosticSnapshot,'RendererInstance'),'EnsureCommunityRenderer'),'communityRenderer')
assert(C.setup(type(renderer)=='table','real renderer instance available for read-only observation'))
local d=Up(renderer.DiagnosticSnapshot,'viewDiagnostic');local pump=d.pump;local jobs=Up(VP.RequestBuilds,'jobs')
local function State()local s,ds=CB.VirtualStats(),CB.DiagnosticSnapshot();return{at=H.now,pumps=VP.WorkStats().communityPumps,publications=VP.WorkStats().publications,binds=s.dataBinds,failures=s.dataFailures,error=s.lastDataError or false,current=ds.projectionCurrent,pending=ds.projectionPending,reason=ds.blockedReason,deadline=pump.failBackoffUntil,job=jobs.builds~=nil,importPending=s.savedImport.pending,receiving=Nexus.Sync.IsReceiving()}end
assert(C.setup(Nexus.StartupStatus().state=='ready' and type(debugprofilestop)=='function','actual startup/default profiler'))
Step(100)
local requested,why=Nexus.Sync.RequestSync()
assert(C.setup(requested~=false and Until(1000,function()return Nexus.Sync.IsReceiving()end)~=nil and #H.sent>0,
 'real public manual Sync request traverses synthetic transport and opens production receive window',why))
CB.Show();local frame=NexusCommunityBuildsFrame
local initial=State()
assert(C.setup(initial.receiving and initial.binds==0 and initial.pending and jobs.builds~=nil,'cold receive Show requests genuine projection without published rows'))
assert(C.setup(Until(100,function()return VP.WorkStats().communityPumps>initial.pumps end)~=nil
 and jobs.builds~=nil and CB.VirtualStats().dataBinds==0 and not CB.DiagnosticSnapshot().projectionCurrent,
 'one real production pump advances cold job without publishing the Library'))
local retained=jobs.builds;local before=State()
local class=frame._classDropBtn;local setter=class.SetText;local callback=frame:GetScript('OnUpdate')
local calls,throws={},0
class.SetText=function(self,...)
 local inFrame=false
 for i=2,50 do local info=debug.getinfo(i,'f');if not info then break end;if info.func==callback then inFrame=true end end
 calls[#calls+1]={at=H.now,inFrame=inFrame,pumps=VP.WorkStats().communityPumps,publications=VP.WorkStats().publications,deadline=pump.failBackoffUntil,sameJob=jobs.builds==retained,trace=debug.traceback('actual cold class label',2)}
 if faulted then throws=throws+1;error('Independent persistent cold receive host failure',0)end
 return setter(self,...)
end
assert(C.setup(Until(100,function()return #calls>0 end)~=nil and calls[1].inFrame
 and calls[1].sameJob and Nexus.Sync.IsReceiving(),'actual cold receive frame callback reaches selected host seam with retained job'))
local after=State();local sameTickCalls=#calls
if faulted then
 C.expect(after.pumps==calls[1].pumps,'newly retained host failure stops positive projection work in the same OnUpdate',F.Serialize(after))
 C.expect(after.publications==calls[1].publications,'newly retained host failure stops same-frame projection publication',F.Serialize(after))
 C.expect(sameTickCalls==1,'newly armed failure hold prevents a second guarded render in the same OnUpdate',sameTickCalls)
else
 C.guard(after.pumps>before.pumps and after.publications>before.publications and after.current,'healthy matched cold frame positively pumps, publishes and binds')
end
C.guard(after.failures==(faulted and throws or 0) and escaped==0,'actual host exceptions are retained once each and contained')
if faulted then
 C.guard(after.deadline>after.at,'actual retained host error arms a future deadline')
 local deadline=after.deadline
 Step(40)
 C.expect(#calls==1 and VP.WorkStats().communityPumps==after.pumps,
  'ordinary frames inside the first400ms hold do not retry the cold host or advance its job')
 C.guard(pump.failBackoffUntil==deadline,'contained ordinary frames do not slide the recorded deadline')
end
class.SetText=setter
C.guard(Until(2000,function()return CB.DiagnosticSnapshot().projectionCurrent and CB.VirtualStats().lastDataError==nil end)~=nil,'restored host eventually publishes healthy Library')
C.guard(#H.actions==0 and #H.sent>0 and #H.sent<=10,'only bounded synthetic manual Sync traffic; no gameplay action')
print('COLD_RECEIVE',F.Serialize({faulted=faulted,initial=initial,before=before,after=after,final=State(),sameTickCalls=sameTickCalls,throws=throws,calls=calls,syntheticSent=H.sent}))
end)
end

-- Automatic replacement is deferred until the first ordinary tick after the hold.
-- The cancelled job cannot claim pending work; explicit Refresh remains immediate.
for _,kind in ipairs({'handled','thrown'}) do
C.scenario('replacement-'..kind..'-posthold-message',function()
 local H=F.Boot(F.Database(),function(h)h.playerLevel=60;h.perks.serverBuildSlots={}end)
 local CB,VP=Nexus.CommunityBuilds,Nexus.ViewProjections
 local function Up(fn,name)for i=1,60 do local k,v=debug.getupvalue(fn,i);if not k then return end;if k==name then return v end end end
 local renderer=Up(Up(Up(CB.DiagnosticSnapshot,'RendererInstance'),'EnsureCommunityRenderer'),'communityRenderer')
 local pump=Up(renderer.DiagnosticSnapshot,'viewDiagnostic').pump
 local read,begin=Nexus.DpsCapture.CommunityEligibilityCursorNext,Nexus.DpsCapture.BeginCommunityEligibilityCursor
 local firstAt,newAt,armed,reads,requests,newAttempts=nil,nil,false,0,0,0
 local older='Original cancelled projection failure'
 local newer=kind=='handled' and 'DPS eligibility cursor unavailable' or 'New replacement label failure'
 local hostCalls,hostAtFailure,requestsAtFailure,pumpsAtFailure,publicationsAtFailure=0,0,0,0,0
 Nexus.DpsCapture.CommunityEligibilityCursorNext=function(...)
  reads=reads+1
  if not firstAt then
   H.now=H.now+.037;firstAt=H.now;armed=true
   hostAtFailure=hostCalls;requestsAtFailure=requests
   pumpsAtFailure=VP.WorkStats().communityPumps;publicationsAtFailure=VP.WorkStats().publications
   return false,older
  end
  return read(...)
 end
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=function(...)
  requests=requests+1
  if armed and kind=='handled' then
   armed=false;newAttempts=newAttempts+1;H.now=H.now+.023;newAt=H.now;return nil
  end
  return begin(...)
 end
 CB.Show();local label=NexusCommunityBuildsFrame._classDropBtn;local setter=label.SetText
 label.SetText=function(self,...)
  hostCalls=hostCalls+1
  if armed and kind=='thrown' then
   armed=false;newAttempts=newAttempts+1;H.now=H.now+.023;newAt=H.now;error(newer,0)
  end
  return setter(self,...)
 end
 for _=1,200 do if firstAt then break end;H.Advance(.01,.01)end
 assert(C.setup(firstAt~=nil and reads==1,'actual production frame pump reaches one cancelled-job failure'))
 local first=CB.VirtualStats();local firstDeadline=firstAt+.5
 C.guard(VP.WorkStats().communityPumps==pumpsAtFailure+1,'original failed pump increments its completed pump counter exactly once')
 C.expect(newAttempts==0 and requests==requestsAtFailure and hostCalls==hostAtFailure,'failed pump performs no inline replacement request or render')
 C.expect(not CB.DiagnosticSnapshot().projectionPending and CB.DiagnosticSnapshot().projectionDirty,'known cancelled job is dirty without false pending progress')
 C.expect(first.dataFailures==1 and first.lastDataError==older and math.abs(pump.failBackoffUntil-firstDeadline)<1e-6,'first failure retains its own message/count/completion deadline')
 while H.now<firstDeadline-.02 do H.Advance(.01,.01)end
 C.expect(newAttempts==0 and requests==requestsAtFailure and hostCalls==hostAtFailure and VP.WorkStats().communityPumps==pumpsAtFailure+1
  and VP.WorkStats().publications==publicationsAtFailure,'entire active hold has no replacement render/request/pump/publication')
 for _=1,50 do if newAttempts>0 then break end;H.Advance(.01,.01)end
 assert(C.setup(newAttempts==1 and newAt~=nil,'first post-hold attempt reaches real replacement refusal or host throw'))
 local latest=CB.VirtualStats()
 C.expect(newAt>=firstDeadline and newAt<=firstDeadline+.2,'replacement occurs on first ordinary post-hold cadence')
 C.expect(latest.dataFailures==2 and latest.lastDataError==newer,'actual newer handled/thrown failure increments count and owns newest diagnostic')
 C.expect(math.abs(pump.failBackoffUntil-(newAt+1))<1e-6,'second actual failure anchors its one-second hold at completion')
 C.guard(not CB.DiagnosticSnapshot().projectionPending and not CB.DiagnosticSnapshot().projectionCurrent,'failed replacement does not invent a pending job or successful publication')
 Nexus.DpsCapture.CommunityEligibilityCursorNext=read;Nexus.DpsCapture.BeginCommunityEligibilityCursor=begin;label.SetText=setter
 C.guard(Settle(H,CB,300)~=nil and CB.VirtualStats().lastDataError==nil,'restored dependencies recover automatically after second hold')
 C.guard(#H.actions==0 and #H.sent==0,'replacement timing sends no gameplay/transport action')
 print('POSTHOLD_REPLACEMENT',F.Serialize({kind=kind,firstAt=firstAt,newAt=newAt,firstDeadline=firstDeadline,latestFailures=latest.dataFailures,latestError=latest.lastDataError}))
end)
end

-- Public diagnostic byte boundaries and protected error formatting.
for _,route in ipairs({'status','view'}) do
for _,kind in ipairs({'utf2','utf3','utf4','ascii','unprintable','healthy'}) do
C.scenario('diagnostic-utf8-'..route..'-'..kind,function()
-- Isolated public-entry evidence. No canonical source or private state writes.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local H=F.Boot(F.Database(),function(h) h.playerLevel=60;h.perks.serverBuildSlots={} end)
local CB=Nexus.CommunityBuilds
local function Step(n) for _=1,n do H.Advance(.01,.01) end end
CB.Show();Step(200)
assert(C.setup(CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending,'real public Library startup settled'))
assert(C.setup(jit.status() and NEXUS_TEST_NO_PROFILE_CLOCK~=true,'default JIT and profiler remain enabled'))
local prefix="Library display failed for saved build '"..string.rep('Arcane Mage ',20)
prefix=prefix..string.rep('x',299-#prefix)
assert(C.setup(#prefix==299,'selected multibyte character starts exactly at byte300'))
local tail=kind=='utf2' and string.char(195,169) or kind=='utf3' and string.char(231,149,140)
 or kind=='utf4' and string.char(240,159,148,165) or 'ASCII title suffix'
local message=prefix..tail.."': label could not be displayed"
local tostringCalls=0
local value=kind=='unprintable' and setmetatable({}, {__tostring=function() tostringCalls=tostringCalls+1;error('secondary tostring fault',0) end}) or message
local healthy=kind=='healthy'
local target,original,field
if route=='status' then
 CB.ShowPostBuild();target=assert(NexusPostPopup)._shareStatus;original=target.SetText;field='lastStatusError'
elseif route=='view' then
 target=assert(NexusCommunityBuildsFrame)._classDropBtn;original=target.SetText;field='lastDataError'
else error('unknown route') end
local calls,trace=0,nil
target.SetText=function(self,...)
 calls=calls+1;trace=debug.traceback('public host seam',2)
 if not healthy then error(value,0) end
 return original(self,...)
end
local ok,err=pcall(CB.Refresh)
local stats,diag=CB.VirtualStats(),CB.DiagnosticSnapshot()
local actual=stats[field]
assert(C.setup(calls==1,'public facade reached selected real host label exactly once'))
C.guard(healthy and ok or not healthy and (route=='status' and ok or route=='view' and not ok and err==value),'public containment or exact original rethrow is preserved')
if healthy then C.expect(actual==nil,'healthy public refresh retains no diagnostic error')
elseif kind=='unprintable' then
 C.expect(actual=='<unprintable value>' and tostringCalls>0,'throwing tostring is safely formatted through actual Errors.SafeText')
else
 assert(C.setup(Nexus.Identity.ValidUtf8(message) and #message>300,'realistic long input is valid UTF-8 and crosses diagnostic byte bound'))
 C.guard(type(actual)=='string' and #actual<=300,'public diagnostic remains bounded at300 bytes')
 C.expect(Nexus.Identity.ValidUtf8(actual),'public diagnostic remains valid UTF-8')
 C.expect(actual==Nexus.Identity.Utf8Prefix(message,300),'public diagnostic equals complete character prefix at300-byte bound')
end
local hex={};if type(actual)=='string' then for i=math.max(1,#actual-7),#actual do hex[#hex+1]=string.format('%02x',actual:byte(i)) end end
print('UTF8_PUBLIC',F.Serialize({route=route,kind=kind,at=H.now,ok=ok,inputBytes=#message,outputBytes=type(actual)=='string' and #actual or 0,
 outputValid=type(actual)=='string' and Nexus.Identity.ValidUtf8(actual) or false,expectedBytes=#Nexus.Identity.Utf8Prefix(message,300),tailHex=table.concat(hex,' '),
 tostringCalls=tostringCalls,dataFailures=stats.dataFailures,statusFailures=stats.statusFailures,shareStatusError=diag.shareStatusError,trace=trace}))
target.SetText=original;CB.Refresh();Step(100)
C.guard(CB.DiagnosticSnapshot().projectionCurrent and CB.VirtualStats()[field]==nil,'restored real host recovers through public refresh')
C.guard(#H.actions==0 and #H.sent==0,'no gameplay or transport actions')

end)
end
end

for _,kind in ipairs({'nil','unprintable','changed','healthy'}) do
C.scenario('latest-error-'..kind,function()
-- Read-only frozen-source proof of newest-error diagnostics through public Refresh.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local H=F.Boot(F.Database(),function(h)h.playerLevel=60;h.perks.serverBuildSlots={}end)
local CB=Nexus.CommunityBuilds
local function Step(n)for _=1,n do H.Advance(.01,.01)end end
CB.Show();Step(200)
assert(C.setup(CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending,'real public Library and import settled'))
assert(C.setup(jit.status() and NEXUS_TEST_NO_PROFILE_CLOCK~=true and Nexus.Errors.SafeText(nil)=='nil','default runtime and actual nil formatter contract'))
local label=NexusCommunityBuildsFrame._classDropBtn;local setter=label.SetText
local old='Older real view label failure';local calls,phase,events,tostringCalls=0,1,{},0
local object=setmetatable({}, {__tostring=function()tostringCalls=tostringCalls+1;error('secondary tostring throw',0)end})
local changed='Newer real view label failure'
label.SetText=function(self,...)
 calls=calls+1;events[#events+1]={at=H.now,phase=phase,stack=debug.traceback('actual public class-label setter',2)}
 if phase==1 then error(old,0) end
 if kind=='nil' then error(nil,0) end
 if kind=='unprintable' then error(object,0) end
 if kind=='changed' then error(changed,0) end
 assert(kind=='healthy');return setter(self,...)
end
local firstOK,firstErr=pcall(CB.Refresh);local before=CB.VirtualStats()
assert(C.setup(not firstOK and firstErr==old and calls==1 and before.lastDataError==old and before.dataFailures==1,'first real public throw is retained exactly once'))
phase=2
local ok,err=pcall(CB.Refresh);local after=CB.VirtualStats();local diagnostic=CB.DiagnosticSnapshot()
assert(C.setup(calls==2,'second public explicit refresh reaches same host during retained failure'))
if kind=='healthy' then
 C.expect(ok and after.lastDataError==nil and diagnostic.projectionCurrent,'healthy replacement publication clears older error')
 C.guard(after.dataFailures==before.dataFailures,'healthy replacement is not counted as a new failure')
else
 C.guard(after.dataFailures==before.dataFailures+1 and not diagnostic.projectionCurrent,'second actual throw counts a new failed view attempt')
 if kind=='nil' then
  C.guard(not ok and err==nil,'public boundary rethrows exact nil value')
  C.expect(after.lastDataError==Nexus.Errors.SafeText(nil),'new nil throw replaces older retained message with literal nil')
 elseif kind=='unprintable' then
  C.guard(not ok and err==object and tostringCalls>0,'throwing tostring preserves original exception object')
  C.expect(after.lastDataError=='<unprintable value>','unprintable new exception replaces older retained evidence safely')
 else
  C.guard(not ok and err==changed,'public boundary preserves changed string exception')
  C.expect(after.lastDataError==changed,'changed string error replaces older retained evidence')
 end
end
print('NIL_PUBLIC',F.Serialize({kind=kind,firstOK=firstOK,secondOK=ok,secondErrIsNil=err==nil,beforeError=before.lastDataError or false,
 afterError=after.lastDataError or false,beforeFailures=before.dataFailures,afterFailures=after.dataFailures,calls=calls,events=events,tostringCalls=tostringCalls}))
label.SetText=setter;CB.Refresh();Step(100)
C.guard(CB.DiagnosticSnapshot().projectionCurrent and CB.VirtualStats().lastDataError==nil,'restored host recovers through real public refresh')
C.guard(#H.actions==0 and #H.sent==0,'no gameplay or transport actions')

end)
end

C.scenario('status-active-error-history',function()
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local H=F.Boot(F.Database(),function(h)h.playerLevel=60;h.perks.serverBuildSlots={}end)
local CB,E=Nexus.CommunityBuilds,Nexus.Errors
local function Step(n)for _=1,n do H.Advance(.01,.01)end end
CB.Show();Step(200);CB.ShowPostBuild()
assert(C.setup(CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending,'real public Library and import settled'))
local popup=assert(NexusPostPopup);local label=popup._shareStatus;local setter=label.SetText
local firstMessage='Persistent Share label font failure';local currentMessage=firstMessage
local calls,events,firstStack=0,{},nil
setter(label,'Previously displayed Share result')
label.SetText=function(self,...)
 calls=calls+1;events[#events+1]={at=H.now,message=currentMessage}
 firstStack=firstStack or debug.traceback('ordinary popup/Library host fault',2)
 error(currentMessage,0)
end
E.Record('Probe.PreviousRootCause','Earlier independent failure retained before popup fault')
local beforeCount=E.SessionCount();local started=H.now
for _=1,18000 do
 Step(1)
 if calls>=21 then break end
end
local persistentCount=E.SessionCount()-beforeCount;local persistentHistory=E.History()
local retainedEarlier,repeats=false,0
for _,entry in ipairs(persistentHistory)do
 if entry.source=='Probe.PreviousRootCause' then retainedEarlier=true end
 if entry.source=='Community.ShareStatus' and entry.message==firstMessage then repeats=repeats+1 end
end
assert(C.setup(calls>=21 and #events>=21,'ordinary registered frame callbacks repeat the persistent host fault at least21 times'))
C.guard(CB.VirtualStats().statusFailures==calls,'every actual failed status attempt is counted independently')
C.guard(CB.VirtualStats().dataFailures==0 and CB.DiagnosticSnapshot().projectionCurrent,'status fault preserves healthy Library current state')
C.expect(persistentCount==1,'same active unchanged status fault records only its first retained evidence',persistentCount)
C.expect(retainedEarlier,'persistent status retry does not evict earlier unrelated evidence',#persistentHistory)
local priorCalls=calls;currentMessage='Changed Share label font failure'
CB.Refresh();local afterChanged=E.Latest();local changedCount=E.SessionCount()-beforeCount
C.guard(calls==priorCalls+1 and afterChanged.message==currentMessage,'new error value is retained on explicit real refresh')
label.SetText=setter;CB.Refresh();local recovered=CB.VirtualStats().lastStatusError==nil
label.SetText=function(self,...)calls=calls+1;error(firstMessage,0)end
CB.Refresh();local afterRecovery=E.Latest();local finalCount=E.SessionCount()-beforeCount
C.guard(recovered and afterRecovery.message==firstMessage and finalCount==changedCount+1,'recovered then recurring failure is a distinct active episode')
label.SetText=setter;CB.Refresh();Step(100)
C.guard(CB.VirtualStats().lastStatusError==nil and #H.actions==0 and #H.sent==0,'restored host recovers with no gameplay/transport action')
local deltas={};for i=2,#events do deltas[#deltas+1]=events[i].at-events[i-1].at end
print('STATUS_RING',F.Serialize({started=started,elapsedTo21=events[21].at-started,firstAt=events[1].at,lastAt=events[21].at,callsAtPersistent=priorCalls,
 sessionRecordsAtPersistent=persistentCount,historySize=#persistentHistory,sameMessageEntries=repeats,earlierRetained=retainedEarlier,
 retryDeltas=deltas,events=events,changedLatestSource=afterChanged.source,recoveredThenRecurringSource=afterRecovery.source,firstStack=firstStack}))

end)

C.scenario('distinct-controller-error-history',function()
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local H=F.Boot(F.Database(),function(h)h.playerLevel=60;h.perks.serverBuildSlots={};h.perks.serverActiveSlot=1 end)
local CB,CAT,E=Nexus.CommunityBuilds,Nexus.BuildCatalog,Nexus.Errors
local function Step(n)for _=1,n do H.Advance(.01,.01)end end
local function Until(n,fn)for i=0,n do if fn() then return i end;if i<n then Step(1)end end end
CB.Show();Step(200)
assert(C.setup(CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending,'real Library and personal import settled'))
local label=NexusCommunityBuildsFrame._classDropBtn;local setter=label.SetText
local message='Same font failure during distinct committed catalog transactions'
local events={}
label.SetText=function(self,...)
 local controller,catalog,lifecycle=false,false,false
 for i=2,50 do local d=debug.getinfo(i,'S');if not d then break end
  controller=controller or d.source=='@core/CommunityController.lua'
  catalog=catalog or d.source=='@core/BuildCatalog.lua'
  lifecycle=lifecycle or d.source=='@core/MainLifecycle.lua'
 end
 if controller and catalog and lifecycle then
  events[#events+1]={at=H.now,stack=debug.traceback('actual committed controller callback',2)}
  error(message,0)
 end
 return setter(self,...)
end
local initialCount=E.SessionCount();local tickets={};local rows={}
for transaction=1,2 do
 local title='Distinct diagnostic transaction '..transaction
 local echoes=L.OrdinaryRows(transaction+1)
 assert(C.setup(L.Copies(echoes)==79 and Nexus.LoadoutEvidence.PublicOrdinaryCompleteness({echoes=echoes}).complete,'actual saved payload has79 complete ordinary copies'))
 H.perks.serverBuildSlots[1]={name=title,verified=true,echoes=echoes};H.Notify();Nexus.GameAdapter.Poll()
 local originalPut=CAT.Put;local ticket,id,puts
 puts=0
 CAT.Put=function(record,...)
  local ok,why,t=originalPut(record,...)
  if record.importedSavedBuild and record.serverTitle==title then ticket=t;id=record.id;puts=puts+1 end
  return ok,why,t
 end
 local beforeCallbacks=#events;local beforeFailures=CAT.DebugStats().mutationCompletionFailures
 CB.Hide();CB.Show()
 assert(C.setup(Until(1000,function()return ticket~=nil end)~=nil and ticket.state=='pending','public reopen import submits an actual pending catalog transaction'))
 tickets[#tickets+1]=ticket
 assert(C.setup(Until(2000,function()return #events>beforeCallbacks end)~=nil and ticket.committed,'real lifecycle completion reaches controller host callback'))
 local caught=E.Latest()
 C.expect(caught.source=='Community.ControllerRefresh' and caught.message==message,'each distinct contained controller failure retains its evidence')
 C.guard(E.SessionCount()==initialCount+transaction,'one entry per committed transaction without duplicated callbacks')
 C.guard(Until(2000,function()return CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending and CB.VirtualStats().lastDataError==nil end)~=nil,'actual healthy publication completes and clears active view failure')
 C.guard(CAT.Get(id) and puts==1 and CAT.DebugStats().mutationCompletionFailures==beforeFailures,'catalog commits exactly once and completion failure count is unchanged')
 rows[#rows+1]={transaction=transaction,puts=puts,committed=ticket.committed,id=id,at=H.now,sessionCount=E.SessionCount()-initialCount}
 CAT.Put=originalPut
end
label.SetText=setter
C.guard(tickets[1]~=tickets[2] and #events==2,'two different real tickets each produce one isolated callback observation')
C.guard(#H.actions==0 and #H.sent==0 and jit.status() and NEXUS_TEST_NO_PROFILE_CLOCK~=true,'default runtime and no gameplay/transport actions')
print('CONTROLLER_TRANSACTIONS',F.Serialize({transactions=rows,events=events,history=E.History(),newRecords=E.SessionCount()-initialCount}))

end)

C.scenario('public-refresh-metric-attribution',function()
-- Evidence-only attribution probe: real TOC/owner paths and public metrics.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local function check(ok,label)return C.expect(ok,label)end
local function Require(ok,label)return assert(C.setup(ok,label))end
local early,bootHarness
local H=F.Boot(F.Database(),function(h)
 bootHarness=h;h.playerLevel=60;h.perks.serverBuildSlots={};h.perks.serverActiveSlot=1
end,function()
 local state=Nexus.StartupStatus().state
 local a,b=Nexus.CommunityBuilds.RefreshAutomatic()
 local c,d=Nexus.CommunityBuilds.Refresh()
 local frameAbsent=true
 for _,frame in ipairs(bootHarness.frames)do if frame:GetName()=='NexusCommunityBuildsFrame' then frameAbsent=false end end
 early={state=state,automatic=a,automaticWhy=b,explicit=c,explicitWhy=d,
  frameAbsent=frameAbsent}
end)
local CB,A,CAT,P=Nexus.CommunityBuilds,Nexus.GameAdapter,Nexus.BuildCatalog,Nexus.Performance
Require(Nexus.StartupStatus().state=='ready','SETUP real TOC startup ready')
Require(early.state~='ready' and early.automatic==false and early.automaticWhy=='pending'
 and early.explicit==false and early.explicitWhy=='pending' and early.frameAbsent,
 'SETUP public explicit/automatic gates reject actual startup without Library frame')
print('STARTUP publicGates=true frameAbsent=true')
local function Step(n)for i=1,n do H.Advance(.01,.01)end end
local function Until(n,fn)
 for i=0,n do if fn() then return i end;if i<n then Step(1)end end
 error('SETUP bounded condition not reached',0)
end
CB.Show();Step(100)
Until(2000,function()
 return not CB.VirtualStats().savedImport.pending and CB.DiagnosticSnapshot().projectionCurrent
  and CAT.RootState().candidate~=true and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil
end)
local frame=NexusCommunityBuildsFrame
Require(frame and frame:IsShown() and frame._classDropBtn,'SETUP actual shown Library host control')
local originalText=frame._classDropBtn.SetText
local calls,controllerCalls,activeTag=0,0,'none'
local function IsCompletion()
 local controller,catalog,lifecycle=false,false,false
 for i=2,45 do
  local info=debug.getinfo(i,'S');if not info then break end
  controller=controller or info.source=='@core/CommunityController.lua'
  catalog=catalog or info.source=='@core/BuildCatalog.lua'
  lifecycle=lifecycle or info.source=='@core/MainLifecycle.lua'
 end
 return controller and catalog and lifecycle
end
frame._classDropBtn.SetText=function(...)
 calls=calls+1
 if IsCompletion() then controllerCalls=controllerCalls+1 end
 return originalText(...)
end
local clock=0
Require(P.SetClock(function()clock=clock+2;return clock end),'SETUP supported metrics clock')
P.SetEnabled(true)
-- Only Performance's supported injected clock is deterministic. The game and
-- scheduler clocks and debugprofilestop remain the ordinary harness versions.
local function MetricReset(tag)
 activeTag=tag;calls,controllerCalls=0,0
 Require(P.Reset('community.refresh'))
end
local function Observe(tag)
 local stats=P.Stats('community.refresh')
 local crumbs=0
 for _,op in ipairs(P.RecentOperations(H.now-1,H.now,H.now))do
  if op.name=='community.refresh' then crumbs=crumbs+1 end
 end
 print('METRIC tag='..tag..' count='..stats.count..' hostCalls='..calls
  ..' controllerCalls='..controllerCalls..' breadcrumbs='..crumbs)
 return stats.count,crumbs
end

MetricReset('explicit')
CB.Refresh()
local count,crumbs=Observe('explicit')
Require(calls==1,'SETUP explicit refresh reaches real host once')
check(count==1 and crumbs==1,'existing explicit Refresh records exactly one aggregate and breadcrumb')

MetricReset('automatic')
CB.RefreshAutomatic()
count,crumbs=Observe('automatic')
Require(calls==1,'SETUP automatic refresh reaches real host once')
check(count==1,'automatic refresh retains existing community.refresh attribution')
check(crumbs==1,'automatic refresh retains community.refresh breadcrumb')

-- Measure records completed callbacks only; exceptions preserve exact values.
MetricReset('explicit-throw')
frame._classDropBtn.SetText=function()error('Metric explicit host fault',0)end
local explicitOK,explicitError=pcall(CB.Refresh)
local explicitCount,explicitCrumbs=Observe('explicit-throw')
C.guard(not explicitOK and explicitError=='Metric explicit host fault' and explicitCount==0 and explicitCrumbs==0,
 'existing explicit Measure path preserves throw and records no completed sample')
frame._classDropBtn.SetText=function(...)return originalText(...)end
CB.Refresh()
MetricReset('automatic-throw')
frame._classDropBtn.SetText=function()error('Metric automatic host fault',0)end
local thrown,why=pcall(CB.RefreshAutomatic)
C.guard(not thrown and why=='Metric automatic host fault','automatic measurement preserves exact thrown value')
count,crumbs=Observe('automatic-throw')
C.guard(count==explicitCount and crumbs==explicitCrumbs,'automatic throw matches existing explicit zero-completed-sample convention')
frame._classDropBtn.SetText=function(...)
 calls=calls+1;if IsCompletion() then controllerCalls=controllerCalls+1 end
 return originalText(...)
end
CB.Refresh()
MetricReset('scheduled')
local views=P.Stats('views.refresh').count
Require(Nexus.ViewRefresh.Request(),'SETUP actual scheduler request accepted')
local scheduledFrames=Until(200,function()return P.Stats('views.refresh').count>views end)
count,crumbs=Observe('scheduled')
Require(calls>0 and scheduledFrames>0,'SETUP scheduled view refresh reached actual Library host')
print('ENCLOSING tag=scheduled views='..(P.Stats('views.refresh').count-views))
check(count>0,'scheduled ViewRefresh retains community.refresh attribution')

-- Submit a real complete saved mirror and observe its catalog callback; no
-- callback replacement, private state injection, or manual ticket completion.
local rows=L.OrdinaryRows(2)
Require(L.Copies(rows)==79,'SETUP real complete nonempty ordinary rows')
local title='Independent metric completion'
H.perks.serverBuildSlots[1]={name=title,verified=true,echoes=H.Clone(rows)}
H.Notify();A.Poll()
local realPut=CAT.Put
local ticket,id,putCalls
putCalls=0
CAT.Put=function(record,...)
 local ok,why,t=realPut(record,...)
 if record and record.importedSavedBuild and record.serverTitle==title then
  putCalls=putCalls+1;ticket,id=t,record.id
 end
 return ok,why,t
end
CB.Hide();CB.Show()
Until(1000,function()return ticket~=nil end)
CAT.Put=realPut
Require(ticket.state=='pending' and type(ticket.completionCallback)=='function' and putCalls==1,
 'SETUP actual import submits one pending ticket retaining its real callback')
MetricReset('controller')
local lifecycle=P.Stats('lifecycle.update').count
local catalog=P.Stats('lifecycle.phase.catalog').count
local completionFrames=Until(2000,function()return ticket.state~='pending' end)
count,crumbs=Observe('controller')
local record=CAT.Get(id)
Require(ticket.state=='committed' and ticket.completionCallback==nil
 and record and record.serverTitle==title and L.Copies(record.echoes)==79
 and controllerCalls==1 and completionFrames>0,'SETUP real callback rendered once and committed nonempty ticket')
Require(not CB.VirtualStats().savedImport.pending,'SETUP original callback finished real import')
print('ENCLOSING tag=controller lifecycle='..(P.Stats('lifecycle.update').count-lifecycle)
 ..' catalog='..(P.Stats('lifecycle.phase.catalog').count-catalog)
 ..' committed=true importComplete=true')
check(count>0,'controller catalog completion retains community.refresh attribution')

frame._classDropBtn.SetText=originalText
Require(P.SetClock(nil),'SETUP restore default metric clock')
print('RESTORED host='..tostring(frame._classDropBtn.SetText==originalText)
 ..' catalog='..tostring(CAT.Put==realPut)..' metricsClock=true')

end)

-- Evidence-only real-TOC probe. Never assigns renderer/job flags or replaces
-- RenderRefresh, List, RequestBuilds, PumpBuilds, or revision/scheduler behavior.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local function Up(fn,name)
 for i=1,60 do local k,v=debug.getupvalue(fn,i);if not k then return end;if k==name then return v end end
end
for _,kind in ipairs({'current','dps','build'}) do
C.scenario('pending-revision-'..kind,function()
 local H=F.Boot(F.Database(),function(h)h.playerLevel=60;h.perks.serverBuildSlots={}end)
 local CB,VP,R,P=Nexus.CommunityBuilds,Nexus.ViewProjections,Nexus.Revisions,Nexus.Performance
 local escaped=0
 local function Step(n)
  for _=1,n do local ok,err=pcall(H.Advance,.01,.01);if not ok then escaped=escaped+1;print('FRAME_ERROR '..tostring(err))end end
 end
 local function Until(n,fn)
  for i=0,n do if fn()then return i end;if i<n then Step(1)end end
 end
 local renderer=Up(Up(Up(CB.DiagnosticSnapshot,'RendererInstance'),'EnsureCommunityRenderer'),'communityRenderer')
 assert(C.setup(type(renderer)=='table','actual startup renderer available for read-only observation'))
 local pump=Up(renderer.DiagnosticSnapshot,'viewDiagnostic').pump
 local jobs=Up(VP.RequestBuilds,'jobs')
 assert(C.setup(type(jobs)=='table','actual production job table available read-only'))
 local function State()
  local d,s,w=CB.DiagnosticSnapshot(),CB.VirtualStats(),VP.WorkStats()
  return {at=H.now,current=d.projectionCurrent,pending=d.projectionPending,dirty=d.projectionDirty,
   reason=d.blockedReason,error=s.lastDataError or false,failures=s.dataFailures,binds=s.dataBinds,
   pumps=w.communityPumps,publications=w.publications,cancellations=w.cancellations,
   sourceRows=w.sourceRows,joins=w.joins,copies=w.copies,deadline=pump.failBackoffUntil,
   job=jobs.builds~=nil,jobKey=jobs.builds and jobs.builds.key or false,
   jobPhase=jobs.builds and jobs.builds.phase or false,importPending=s.savedImport.pending,
   dpsRevision=R.Get(R.DPS_CHANGED),buildRevision=R.Get(R.BUILD_LIBRARY_CHANGED),
   viewRefreshes=P.Stats('views.refresh').count}
 end
 Step(100);P.SetEnabled(true)
 assert(C.setup(Nexus.StartupStatus().state=='ready' and not Nexus.Sync.IsReceiving()
  and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil,'ready nonreceiving startup scheduler drained'))
 local read=Nexus.DpsCapture.CommunityEligibilityCursorNext
 local seamCalls,failedAt,faultTrace=0,nil,nil
 Nexus.DpsCapture.CommunityEligibilityCursorNext=function(...)
  seamCalls=seamCalls+1
  if seamCalls==1 then failedAt=H.now;faultTrace=debug.traceback('real production eligibility failure',2);return false,'Independent one-shot cursor failure' end
  return read(...)
 end
 CB.Show()
 assert(C.setup(Until(200,function()return CB.VirtualStats().dataFailures>0 end)~=nil,'actual frame pump reaches handled dependency failure'))
 Nexus.DpsCapture.CommunityEligibilityCursorNext=read
 -- Explicit Refresh is allowed to request immediately after a cancelled job.
 local explicit,why=CB.Refresh()
 assert(C.setup(explicit==false and why=='pending','public explicit refresh supplies genuine pending work during hold'))
 local before=State();local retained=jobs.builds
 assert(C.setup(seamCalls==1 and type(retained)=='table' and before.pending and not before.current
  and before.failures==1 and before.reason=='projection-error' and before.deadline>H.now,
  'one real handled failure leaves real replacement job pending inside first hold'))
 local event=kind=='dps' and R.DPS_CHANGED or kind=='build' and R.BUILD_LIBRARY_CHANGED or nil
 local scheduledDue=false
 if event then
  local old=R.Get(event)
  assert(C.setup(R.Advance(event,{scope='all',reason='independent stale pending repro'})==old+1,'public revision token advances once'))
  local pending=Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())
  scheduledDue=pending and pending.due or false
  assert(C.setup(scheduledDue and scheduledDue<before.deadline,'real coalesced revision refresh is due within retained hold'))
 end
 Step(12)
 local held=State()
 C.guard(held.at<before.deadline and held.deadline==before.deadline and held.pumps==before.pumps,
  'first 120ms preserves failure deadline and performs no held projection work')
 C.guard(jobs.builds==retained,'held observation does not mutate the actual production job')
 if event then
  C.expect(not held.pending and held.dirty and not held.current,'changed revision invalidates only stale pending truth during hold')
  C.guard(held.failures==before.failures and held.error==before.error,'revision invalidation preserves active failure evidence')
 else C.guard(held.pending,'unchanged pending request retains truthful pending state') end
 if event then
  assert(C.setup(held.viewRefreshes==before.viewRefreshes+1
   and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil,'real scheduler refresh executes once and drains during hold'))
 end
 local firstWork,firstMissing,firstSame
 while H.now<before.deadline+.2-.00000001 do
  Step(1)
  if not firstWork and VP.WorkStats().communityPumps>before.pumps then firstWork=State();firstSame=jobs.builds==retained end
  if not firstMissing and not jobs.builds and not CB.DiagnosticSnapshot().projectionCurrent then firstMissing=State()end
 end
 local due=State()
 if event then
  C.expect(firstWork~=nil,'changed revision resumes positive projection work within hold plus 200ms',F.Serialize(due))
  C.expect(not due.pending or due.job,'public pending diagnostic corresponds to an actual live production job',F.Serialize(due))
 else
  C.guard(firstWork~=nil and firstSame,'unchanged revision advances the same retained production job within hold plus 200ms',F.Serialize(firstWork))
 end
 C.guard(not firstWork or firstWork.at+.00000001>=before.deadline,'ordinary work never releases the original failure hold early')
 local finishFrames=Until(2000,function()
  if not firstWork and VP.WorkStats().communityPumps>before.pumps then firstWork=State();firstSame=jobs.builds==retained end
  return CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending
 end)
 local final=State()
 C.guard(finishFrames~=nil and final.current and not final.pending and final.error==false,'bounded safety path eventually publishes after restored dependency')
 C.guard(final.failures==1 and escaped==0,'restoration creates no new failure or escaping frame')
 C.guard(#H.actions==0 and #H.sent==0,'no synthetic gameplay or transport action')
 print('OBSERVATION '..F.Serialize({kind=kind,failedAt=failedAt,faultTrace=faultTrace,
  scheduledDue=scheduledDue,before=before,held=held,due=due,firstMissing=firstMissing or false,
  firstWork=firstWork or false,firstWorkSameJob=firstSame or false,final=final,seamCalls=seamCalls,
  jitEnabled=jit.status(),defaultProfiler=type(debugprofilestop)=='function'}))
end)
end

-- Independent F3 probe. All production functions execute except one public
-- cursor acquisition which refuses with nil in the fault arm. A pass-through
-- currentness observer advances the real revision at the safety-read boundary.
-- Its real cursor acquisition advances harness time37ms in both arms only; clocks/JIT are not replaced.
local F=dofile('tests/prototype/format5_support.lua')
local function Check(kind,ok,label)
 if kind=='SETUP' then return C.setup(ok,label) end
 if kind=='GUARD' then return C.guard(ok,label) end
 return C.expect(ok,label)
end
local function Up(fn,name)
 assert(type(fn)=='function','upvalue owner '..name)
 for i=1,60 do local k,v=debug.getupvalue(fn,i);if not k then return end;if k==name then return v end end
end
for _,faulted in ipairs({false,true}) do
C.scenario(faulted and 'safety-refusal-anchor' or 'safety-healthy-anchor',function()
 local H=F.Boot(F.Database(),function(h)
  h.playerLevel=60;h.perks.serverBuildSlots={};h.perks.serverActiveSlot=1
 end)
 local CB,VP=Nexus.CommunityBuilds,Nexus.ViewProjections
 local renderer=Up(Up(Up(CB.DiagnosticSnapshot,'RendererInstance'),'EnsureCommunityRenderer'),'communityRenderer')
 local d=Up(renderer.DiagnosticSnapshot,'viewDiagnostic');local pump=d.pump
 local jobs=Up(VP.RequestBuilds,'jobs')
 local function State()
  local s,ds=CB.VirtualStats(),CB.DiagnosticSnapshot()
  return {at=GetTime(),current=ds.projectionCurrent,pending=ds.projectionPending,
   dirty=ds.projectionDirty,reason=ds.blockedReason,failures=s.dataFailures,
   error=s.lastDataError or false,deadline=pump.failBackoffUntil,
   noted=pump.failuresNoted or 0,job=jobs.builds~=nil,
   pumps=VP.WorkStats().communityPumps,publications=VP.WorkStats().publications,
   binds=s.dataBinds,importPending=s.savedImport.pending}
 end
 local escaped=0
 local function Step(delta)
  local ok,err=pcall(H.Advance,delta or .01,delta or .01)
  if not ok then escaped=escaped+1;print('ESCAPE',err) end
 end
 local function Until(limit,predicate)
  for i=0,limit do if predicate() then return i end;if i<limit then Step() end end
 end
 print('ARM',faulted and 'fault' or 'healthy')
 assert(Check('SETUP',Nexus.StartupStatus().state=='ready','real TOC startup ready'))
 CB.Show();for i=1,100 do Step() end
 assert(Check('SETUP',Until(2000,function()
  return CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending
   and Nexus.Scheduler.Pending(Nexus.ViewRefresh.Key())==nil and not Nexus.Sync.IsReceiving()
 end)~=nil,'warm current view with scheduler/import/receive settled'))
 local before=State()
 assert(Check('SETUP',before.failures==0 and not before.job and not before.dirty,
  'no initial failure, job or dirty projection'))
 local update=NexusCommunityBuildsFrame:GetScript('OnUpdate')
 local function InUpdate()
  for i=2,50 do local d=debug.getinfo(i,'f');if not d then break end;if d.func==update then return true end end
  return false
 end
 local nativeCurrent=VP.BuildsCurrent
 local nativeBegin=Nexus.DpsCapture.BeginCommunityEligibilityCursor
 local armed,triggered=false,false
 local safetyTrace,refusalTrace,revisionBefore,revisionAfter,returnedCurrent
 local acquired,refusals=0,0
 local cursorEnteredAt,cursorCompletedAt
 VP.BuildsCurrent=function(...)
  local trace=debug.traceback('currentness boundary',2)
  if armed and not triggered and InUpdate() then
   triggered=true;safetyTrace=trace
   revisionBefore=Nexus.Revisions.Get(Nexus.Revisions.DPS_CHANGED)
   revisionAfter=Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source='independent F3 boundary'})
   returnedCurrent=nativeCurrent(...)
   return returnedCurrent
  end
  return nativeCurrent(...)
 end
 Nexus.DpsCapture.BeginCommunityEligibilityCursor=function(...)
  acquired=acquired+1
  if triggered and acquired==1 then
   cursorEnteredAt=GetTime();H.now=H.now+.037;cursorCompletedAt=GetTime()
   refusalTrace=debug.traceback('actual cursor acquisition',2)
   if faulted then refusals=refusals+1;return nil end
  end
  return nativeBegin(...)
 end
 armed=true
 assert(Check('SETUP',Until(1000,function()return triggered end)~=nil,'actual eight-second safety currentness read reached'))
 local immediate=State()
 Check('GUARD',revisionAfter==revisionBefore+1 and returnedCurrent==false,
  'real public DPS revision makes delegated currentness false')
 Check('GUARD',acquired==1 and refusalTrace and triggered and cursorEnteredAt-before.at>=6.9,
  'real safety RenderRefresh reaches real RequestBuilds acquisition once')
 Check('GUARD',cursorCompletedAt and math.abs(cursorCompletedAt-cursorEnteredAt-.037)<1e-6,
  'synthetic acquisition advances clock by 37ms in both arms')
 if faulted then
  Check('GUARD',refusals==1 and immediate.failures==1 and immediate.error=='DPS eligibility cursor unavailable'
   and not immediate.pending and not immediate.job and immediate.reason=='projection-error',
   'handled nil acquisition becomes one truthful projection failure, no job or pending flag')
  Check('EXPECT',math.abs(immediate.deadline-(cursorCompletedAt+.5))<1e-6,
   'handled safety failure arms first 500ms hold before the frame returns')
 else
  Check('GUARD',refusals==0 and immediate.failures==0 and immediate.pending and immediate.job,
   'healthy identical revision creates a real pending job without failure')
  Check('EXPECT',immediate.deadline==0,'healthy pending work does not acquire failure hold')
 end
 Step(.02)
 local nextFrame=State()
 if faulted then
  Check('GUARD',nextFrame.failures==1 and nextFrame.noted==1,
   'next frame observes the same single retained failure')
  Check('EXPECT',math.abs(nextFrame.deadline-(cursorCompletedAt+.5))<1e-6,
   'later observation preserves the original failure completion deadline')
 else
  Check('EXPECT',nextFrame.deadline==0 and nextFrame.failures==0,'healthy next frame remains free of failure hold')
 end
 VP.BuildsCurrent=nativeCurrent;Nexus.DpsCapture.BeginCommunityEligibilityCursor=nativeBegin;armed=false
 local recovered=Until(2000,function()return CB.DiagnosticSnapshot().projectionCurrent and CB.VirtualStats().lastDataError==nil end)
 Check('GUARD',recovered~=nil,'restored public dependencies eventually publish a healthy current view')
 Check('GUARD',escaped==0 and #H.actions==0 and #H.sent==0,'no frame escape or synthetic gameplay/network operation')
 print('OBSERVED',F.Serialize({faulted=faulted,before=before,immediate=immediate,nextFrame=nextFrame,
  final=State(),cursorEnteredAt=cursorEnteredAt,cursorCompletedAt=cursorCompletedAt,
  revisionBefore=revisionBefore,revisionAfter=revisionAfter,returnedCurrent=returnedCurrent,
  safetyTrace=safetyTrace,refusalTrace=refusalTrace,acquired=acquired,refusals=refusals,
  recoveredFrames=recovered or false,escaped=escaped}))
end)
end

-- Final Spec-Library F1-F4 successor controls use a7ce9eb as RED baseline.
-- Public renderer/controller paths and actual host setters only; no renderer,
-- projection job, clock, revision, or failure-state replacement.
do
local function WarmCards()
 local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
 local fx=L.New({players={{name='FinalCard',class='MAGE',variant=1,title='Final exact binding'}}})
 local db=fx:Install(F.Database())
 db.buildFilters={qualifiedOnly=false,currentClassOnly=true,scope='all',sortMode='title',page=1,search=''}
 local H=F.Boot(db,function(h)h.playerLevel=60;h.perks.serverBuildSlots={}end)
 return H,Nexus.CommunityBuilds
end
local function Cards(H)
 local cards={}
 for _,f in ipairs(H.frames)do
  if f.buildId and f.title and f.author and f.dpsBreakdown then cards[#cards+1]=f end
 end
 return cards
end
local function FaultCards(H,value)
 local originals,calls={},0
 for _,card in ipairs(Cards(H))do
  originals[card.title]=card.title.SetText
  card.title.SetText=function()calls=calls+1;error(value,0)end
 end
 return function()return calls end,function()
  for label,setter in pairs(originals)do label.SetText=setter end
 end
end
for _,entry in ipairs({'Refresh','Show'})do
C.scenario('final-f1-card-exact-'..entry,function()
 local H,CB=WarmCards();CB.Show()
 assert(C.setup(Settle(H,CB)~=nil and #Cards(H)>0,'real visible card bound before exact-value fault'))
 local values={{kind='string',value='Exact card title failure'},
  {kind='table',value={fault='card'}},{kind='nil'},{kind='false',value=false}}
 for _,case in ipairs(values)do
  local calls,restore=FaultCards(H,case.value);local before=CB.VirtualStats().dataFailures
  local ok,err=pcall(CB[entry]);local s=CB.VirtualStats()
  C.setup(calls()==1,'actual card title host setter throws once: '..entry..'/'..case.kind,calls())
  C.expect(not ok and err==case.value,'card binding rethrows exact '..case.kind..' from '..entry,err)
  C.expect(s.dataFailures==before+1 and s.lastDataError==Nexus.Errors.SafeText(case.value),
   'card fault retains exact bounded evidence once: '..entry..'/'..case.kind,s.lastDataError)
  restore();CB.Refresh()
  C.guard(Settle(H,CB)~=nil and CB.VirtualStats().lastDataError==nil,'restored card recovers through public Refresh')
 end
 C.guard(#H.actions==0 and #H.sent==0,'exact card failures send no gameplay or transport action')
end)
end
C.scenario('final-f1-detail-exact-returned-error',function()
 local H,CB=Boot({value=false});CB.Show()
 assert(C.setup(Settle(H,CB)~=nil,'real detail source settles'))
 local id
 for _,b in pairs(CB.Builds())do if b.importedSavedBuild then id=b.id;break end end
 assert(C.setup(id~=nil,'actual saved mirror is available for public selection'))
 local get=Nexus.BuildCatalog.Get;local message='Exact detail dependency failure';local calls=0
 Nexus.BuildCatalog.Get=function(...)
  for i=2,10 do local info=debug.getinfo(i,'S');if not info then break end
   if info.source=='@core/CommunityProjection.lua' then calls=calls+1;error(message,0)end
  end
  return get(...)
 end
 local ok,err=pcall(CB.Select,id)
 C.setup(calls==1,'real detail projection catches its failing catalog dependency',calls)
 C.expect(not ok and err==message and CB.VirtualStats().lastDataError==message,
  'renderer preserves exact error returned by existing detail projection contract',err)
 Nexus.BuildCatalog.Get=get;CB.Refresh()
 C.guard(Settle(H,CB)~=nil and CB.VirtualStats().lastDataError==nil,'restored detail dependency recovers')
 C.guard(#H.actions==0 and #H.sent==0,'detail control sends no gameplay or transport action')
end)
C.scenario('final-f2-sync-ticker-import-independent',function()
 local receiving={value=true};local H,CB=Boot(receiving)
 CB.Show();NexusCommunityBuildsFrame._myBuildsBtn:Click()
 local label=NexusCommunityBuildsFrame._syncStatusText;local setter=label.SetText
 local calls=0;local message='Automatic receive label host failure'
 label.SetText=function()calls=calls+1;error(message,0)end
 local before=CB.VirtualStats();local escaped=Step(H,30);local held=CB.VirtualStats()
 C.setup(calls>0,'real automatic receive label reaches the persistent host fault')
 C.expect(escaped==0 and calls==1,'automatic sync label failure is contained and held',escaped..'/'..calls)
 C.expect(held.dataFailures==before.dataFailures+1 and held.lastDataError==message,
  'sync label fault belongs to existing view failure owner once',held.lastDataError)
 C.expect(held.savedImport.syncDeferrals-before.savedImport.syncDeferrals==30,
  'sync label exception cannot abort healthy per-frame deferred import checks')
 C.guard(held.statusFailures==before.statusFailures and held.lastStatusError==before.lastStatusError,
  'sync label never touches unrelated Share status failure ledger')
 receiving.value=false;Step(H,1);local nextFrame=CB.VirtualStats()
 C.expect(nextFrame.savedImport.pumps==held.savedImport.pumps+1,
  'first nonreceiving frame advances healthy import inside view failure hold')
 label.SetText=setter
 C.guard(Settle(H,CB)~=nil,'restored sync label and independent import recover')
 C.guard(#H.actions==0 and #H.sent==0,'sync label faults send no gameplay or transport action')
end)
C.scenario('final-f2-resize-held-scroll-explicit',function()
 local H,CB=WarmCards();CB.Show()
 assert(C.setup(Settle(H,CB)~=nil and #Cards(H)>0,'real visible cards settle before cached rebind'))
 local scroll=NexusCommunityBuildsFrame._virtualListScrollFrame
 local resize=scroll:GetScript('OnSizeChanged');local message='Exact cached rebind host failure'
 local calls,restore=FaultCards(H,message);local before=CB.VirtualStats().dataFailures
 local ok,err=pcall(resize,scroll)
 C.setup(calls()==1,'real resize callback reaches actual cached card setter')
 C.expect(ok and CB.VirtualStats().dataFailures==before+1
  and CB.VirtualStats().lastDataError==message,'automatic resize contains and retains exact fault once',err)
 local escaped=0
 for _=1,40 do H.now=H.now+.01;if not pcall(resize,scroll)then escaped=escaped+1 end end
 C.expect(escaped==0 and calls()==1,'repeated automatic resize honors existing view hold',calls())
 local scrolled,scrollErr=pcall(CB.ScrollTo,0)
 C.expect(not scrolled and scrollErr==message and calls()==2,
  'public explicit scroll stays immediate inside hold and exact-rethrows its own fault',scrollErr)
 C.expect(CB.VirtualStats().dataFailures==before+2 and CB.VirtualStats().lastDataError==message,
  'explicit scroll retains its actual new failed attempt')
 restore();CB.Refresh()
 C.guard(Settle(H,CB)~=nil and CB.VirtualStats().lastDataError==nil,'cached binding recovers through successful publication')
 C.guard(CB.VirtualStats().statusFailures==0 and #H.actions==0 and #H.sent==0,'cached rebind preserves status ledger and performs no gameplay action')
end)
for _,held in ipairs({false,true})do
C.scenario('final-f3-mine-cold-receive-'..(held and 'import-held' or 'import-deferred'),function()
 local receiving={value=not held};local H,CB=Boot(receiving)
 local slots=Nexus.GameAdapter.Slots
 if held then Nexus.GameAdapter.Slots=function(...)
  local info=debug.getinfo(2,'S')
  if info and info.source=='@core/CommunityController.lua' then error('Held Mine import Begin',0)end
  return slots(...)
 end end
 CB.Show();NexusCommunityBuildsFrame._myBuildsBtn:Click();receiving.value=true
 local before=CB.VirtualStats();local frame=NexusCommunityBuildsFrame
 C.setup(before.dataBinds==0 and CB.DiagnosticSnapshot().filterScope=='mine',
  'Mine cold receive has not bound a publication')
 C.setup(held and before.importFailures==1 or not held and before.savedImport.pending,
  'real deferred/failed import owns cold Mine wait')
 local writes=0;local setter=frame._classDropBtn.SetText
 frame._classDropBtn.SetText=function(self,...)writes=writes+1;return setter(self,...)end
 local pumps=Nexus.ViewProjections.WorkStats().communityPumps;local escaped=Step(H,100)
 C.expect(writes==0 and Nexus.ViewProjections.WorkStats().communityPumps==pumps,
  'cold Mine pending import performs zero full-refresh churn during receive',writes)
 C.guard(escaped==0 and CB.VirtualStats().dataFailures==0,'waiting Mine does not manufacture view failure')
 frame._classDropBtn.SetText=setter;Nexus.GameAdapter.Slots=slots;receiving.value=false
 C.guard(Settle(H,CB)~=nil and CB.DiagnosticSnapshot().projectionCurrent,
  'Mine resumes genuine import and publication after receive/hold')
 C.guard(#H.actions==0 and #H.sent==0,'cold Mine wait sends no gameplay or transport action')
end)
end
C.scenario('final-f3-all-cold-receive-progresses',function()
 local receiving={value=true};local H,CB=Boot(receiving);CB.Show()
 local before=CB.VirtualStats();local pumps=Nexus.ViewProjections.WorkStats().communityPumps
 local label=NexusCommunityBuildsFrame._classDropBtn;local setter=label.SetText;local writes=0
 label.SetText=function(self,...)writes=writes+1;return setter(self,...)end
 local escaped=Step(H,100);local after=CB.VirtualStats()
 local advanced=Nexus.ViewProjections.WorkStats().communityPumps-pumps
 C.setup(before.dataBinds==0 and before.savedImport.pending,'All starts cold with actual deferred personal import')
 C.guard(escaped==0 and after.dataBinds>0 and advanced>0 and advanced<=10 and writes>0 and writes<=10,
  'All cold receive retains positive publication and bounded100ms refresh/pump cadence',writes..'/'..advanced)
 C.guard(after.savedImport.pending and after.savedImport.syncDeferrals>before.savedImport.syncDeferrals,
  'All progression does not bypass the independent personal receive deferral')
 C.guard(#H.actions==0 and #H.sent==0,'All progression sends no gameplay or transport action')
 label.SetText=setter
end)
C.scenario('final-f4-unchanged-status-is-not-recovery',function()
 local H,CB=Boot({value=false},true);CB.Show()
 assert(C.setup(Settle(H,CB)~=nil,'real Library settles before unchanged status fault'))
 CB.ShowPostBuild();local label=NexusPostPopup._shareStatus;local setter=label.SetText
 local displayed=label:GetText();local message='Persistent unchanged Share setter failure';local calls=0
 label.SetText=function()calls=calls+1;error(message,0)end
 local records=Nexus.Errors.SessionCount();CB.Refresh()
 C.setup(calls==1 and label:GetText()==displayed and CB.VirtualStats().lastStatusError==message,
  'actual explicit setter fails while already displayed status equals desired text')
 -- Isolate the real popup poll: hidden Library has no unrelated data refresh
 -- that could immediately attempt a new status write after the unchanged poll.
 CB.Hide()
 -- Two real 500ms polls cross the strict failure deadline even when binary
 -- frame increments make the first poll land just before that deadline.
 local escaped=Step(H,120)
 C.expect(CB.VirtualStats().lastStatusError==message,
  'unchanged polling cannot erase active status failure without successful host write')
 CB.Refresh()
 C.expect(Nexus.Errors.SessionCount()==records+1,
  'same active failure remains one history episode across unchanged polls',Nexus.Errors.SessionCount()-records)
 C.guard(escaped==0 and CB.VirtualStats().dataFailures==0 and CB.DiagnosticSnapshot().projectionCurrent,
  'status episode does not invalidate or escape healthy Library work')
 label.SetText=setter;CB.Refresh()
 C.guard(CB.VirtualStats().lastStatusError==nil,'actual successful status write proves recovery')
 local recoveredRecords=Nexus.Errors.SessionCount()
 label.SetText=function()error(message,0)end;CB.Refresh()
 C.guard(Nexus.Errors.SessionCount()==recoveredRecords+1,'recurrence after actual successful write starts one new episode')
 label.SetText=setter;CB.Refresh()
 C.guard(#H.actions==0 and #H.sent==0,'status recovery control sends no gameplay or transport action')
end)
end

-- Final Library follow-up: settle real startup maintenance while hidden,
-- before requesting the retained All job. The earlier cold-Mine controls stay
-- intact; these controls remove their incidental revision-cancellation escape.
do
local function Up(fn,wanted)
 for i=1,80 do local name,value=debug.getupvalue(fn,i)
  if not name then break end
  if name==wanted then return value end
 end
 error('missing read-only job upvalue '..wanted,0)
end
for _,arm in ipairs({'healthy','fault','import-held'})do
C.scenario('opus-final-mine-retained-all-'..arm,function()
 local held=arm=='import-held';local faulted=arm=='fault'
 local receiving={value=not held};local H,CB=Boot(receiving)
 C.setup(Step(H,200)==0,'real hidden startup maintenance settles before retained All request')
 local VP,R=Nexus.ViewProjections,Nexus.Revisions
 local jobs=Up(VP.RequestBuilds,'jobs')
 local nextRow=Nexus.DpsCapture.CommunityEligibilityCursorNext;local calls=0
 local slots=Nexus.GameAdapter.Slots
 if held then Nexus.GameAdapter.Slots=function(...)
  local info=debug.getinfo(2,'S')
  if info and info.source=='@core/CommunityController.lua'then error('Held retained-All Mine import',0)end
  return slots(...)
 end end
 if faulted then Nexus.DpsCapture.CommunityEligibilityCursorNext=function()
  calls=calls+1;return false,'Retained All dependency must not run in waiting Mine'
 end end
 CB.Show();local job=jobs.builds
 NexusCommunityBuildsFrame._myBuildsBtn:Click();receiving.value=true
 local revision=R.Get(R.BUILD_LIBRARY_CHANGED);local dps=R.Get(R.DPS_CHANGED)
 local before=VP.WorkStats();local stats=CB.VirtualStats()
 assert(C.setup(job and jobs.builds==job and job.filters.scope=='all'
  and CB.DiagnosticSnapshot().filterScope=='mine'
  and (held and CB.DiagnosticSnapshot().savedImportError or not held and stats.savedImport.pending)
  and not CB.DiagnosticSnapshot().projectionPending,
  'actual current All job is retained while cold Mine has no requested projection'))
 local escaped=Step(H,100);local after=VP.WorkStats()
 C.setup(R.Get(R.BUILD_LIBRARY_CHANGED)==revision and R.Get(R.DPS_CHANGED)==dps,
  'unchanged revisions exclude incidental stale-job cancellation during Mine wait')
 C.expect(after.communityPumps==before.communityPumps and jobs.builds==job
  and after.cancellations==before.cancellations,
  'waiting Mine neither pumps nor publishes its retained All job',after.communityPumps-before.communityPumps)
 C.expect(calls==0 and CB.VirtualStats().dataFailures==stats.dataFailures,
  'waiting Mine does not inherit a retained All dependency failure',calls)
 C.guard(escaped==0 and (held and CB.DiagnosticSnapshot().savedImportError
  and CB.VirtualStats().importFailures>=stats.importFailures
  and CB.VirtualStats().lastImportError=='Held retained-All Mine import'
  or not held and CB.VirtualStats().savedImport.pending
  and CB.VirtualStats().savedImport.syncDeferrals>stats.savedImport.syncDeferrals),
  'real personal import remains independently deferred without frame escape')
 Nexus.DpsCapture.CommunityEligibilityCursorNext=nextRow;Nexus.GameAdapter.Slots=slots;receiving.value=false
 C.guard(Settle(H,CB)~=nil and CB.DiagnosticSnapshot().projectionCurrent
  and not CB.VirtualStats().savedImport.pending,
  'Mine resumes actual import and publication when receive ends')
 C.guard(#H.actions==0 and #H.sent==0,'retained All discrimination sends no game or network action')
end)
end
C.scenario('opus-final-all-current-job-progress',function()
 local receiving={value=true};local H,CB=Boot(receiving)
 C.setup(Step(H,200)==0,'hidden maintenance settles before All control')
 CB.Show();local VP,R=Nexus.ViewProjections,Nexus.Revisions
 local before=VP.WorkStats();local revision=R.Get(R.BUILD_LIBRARY_CHANGED)
 C.setup(CB.DiagnosticSnapshot().projectionPending and CB.VirtualStats().savedImport.pending,
  'All requests a genuine job while personal import waits')
 local escaped=Step(H,100);local after=VP.WorkStats()
 C.guard(after.communityPumps>before.communityPumps and CB.VirtualStats().dataBinds>0,
  'healthy All still advances and publishes during receive')
 C.guard(R.Get(R.BUILD_LIBRARY_CHANGED)==revision and after.cancellations==before.cancellations,
  'positive All progression uses current work without incidental cancellation')
 C.guard(escaped==0 and CB.VirtualStats().savedImport.pending and #H.actions==0 and #H.sent==0,
  'All control preserves independent import deferral and has no actions')
end)
C.scenario('opus-final-dirty-current-pending',function()
 local H,CB=Boot({value=true},true)
 C.setup(Step(H,200)==0,'hidden startup maintenance settles before pending truth test')
 CB.Show();local VP,R=Nexus.ViewProjections,Nexus.Revisions
 local jobs=Up(VP.RequestBuilds,'jobs');local job=jobs.builds
 local revision=R.Get(R.BUILD_LIBRARY_CHANGED);local before=VP.WorkStats()
 assert(C.setup(job and CB.DiagnosticSnapshot().projectionPending,
  'real current projection is pending before same-revision dirty notification'))
 CB.MarkDataDirty()
 C.expect(CB.DiagnosticSnapshot().projectionPending,
  'same-revision MarkDataDirty preserves live pending truth')
 C.guard(jobs.builds==job and R.Get(R.BUILD_LIBRARY_CHANGED)==revision,
  'dirty notification leaves actual job and revision unchanged')
 R.Advance(R.BUILD_LIBRARY_CHANGED);CB.MarkDataDirty()
 C.guard(not CB.DiagnosticSnapshot().projectionPending and CB.DiagnosticSnapshot().projectionDirty,
  'changed revision clears stale pending truth and retains dirty work')
 local after=VP.WorkStats()
 C.guard(after.communityPumps==before.communityPumps and after.cancellations==before.cancellations
  and jobs.builds==job,'pending diagnostic invalidation neither pumps nor cancels actual work')
 C.guard(#H.actions==0 and #H.sent==0,'pending truth observation sends no game or network action')
end)
for _,mode in ipairs({'synchronous','synchronous-fault','ticket'})do
C.scenario('opus-final-detail-finish-'..mode,function()
 local asynchronous=mode=='ticket';local persistent=mode=='synchronous-fault'
 local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
 local H=F.Boot(F.Database(),function(h)h.playerLevel=60;h.perks.serverActiveSlot=1
  h.perks.serverBuildSlots={[1]={name='Refused detail publication',verified=true,echoes=L.OrdinaryRows(3)}}end)
 Nexus.Sync.IsReceiving=function()return false end
 local CB=Nexus.CommunityBuilds;CB.Show()
 assert(C.setup(Settle(H,CB,2500)~=nil,'real saved import and publication settle before detail refusal'))
 local mirror
 for _,b in pairs(CB.Builds())do if b.importedSavedBuild and b.serverSlot==1 then mirror=b end end
 assert(C.setup(mirror~=nil,'real saved mirror exists for public detail action'))
 CB.Select(mirror.id);local detail
 for _,f in ipairs(H.frames)do if f.shareBtn and f.shareBtn.GetText then detail=f end end
 assert(C.setup(detail and detail:IsShown() and detail.shareBtn:IsShown() and detail.shareBtn:GetText()=='Share Build...',
  'actual own saved-mirror detail Share Build... button is visible'))
 local controller=Up(Up(CB.PublishImportedBuild,'ControllerInstance'),'EnsureCommunityController')()
 local publish=controller.PublishImportedBuild;local attempts=0;local callback;local ticket={state='pending'}
 -- Synthetic refusal boundary: the public detail Share Build... click, its actual
 -- NEXUS_SHARE_SAVED_BUILD confirmation Accept and the refresh are real;
 -- the controller cannot enqueue a catalog mutation, share or transport action.
 controller.PublishImportedBuild=function(id,finish)
  attempts=attempts+1;callback=finish
  if asynchronous then return nil,'ROOT_MUTATION_PENDING',ticket end
  return false,'Synthetic synchronous publication refusal'
 end
 local label=NexusCommunityBuildsFrame._classDropBtn;local setter=label.SetText
 local calls=0;local armed=true;local message='Existing detail view hold'
 label.SetText=function(self,...)
  calls=calls+1;if armed or persistent then armed=false;error(message,0)end
  return setter(self,...)
 end
 local ok,err=pcall(CB.Refresh)
 assert(C.setup(not ok and err==message and calls==1 and CB.VirtualStats().lastDataError==message,
  'real host exception establishes a view hold before explicit detail click'))
 local actions,sent=#H.actions,#H.sent
 local priorPopup=H.popup
 local clicked,clickError=pcall(function()detail.shareBtn:Click()end)
 local popup=H.popup
 assert(C.setup(clicked and popup~=nil and popup~=priorPopup and popup.which=='NEXUS_SHARE_SAVED_BUILD'
  and type(popup.data)=='table' and popup.data.id==mirror.id,
  'public detail Share click opens its actual confirmation during the view hold',clickError))
 C.guard(attempts==0 and detail.shareBtn:GetText()=='Share Build...' and #H.actions==actions and #H.sent==sent,
  'open Share confirmation reaches no publisher, game or transport action before Accept',attempts)
 local accepted,acceptError=pcall(H.AcceptPopup)
 if asynchronous then
  assert(C.setup(accepted and attempts==1 and callback and detail.shareBtn:GetText()=='Sharing...',
   'public Share confirmation retains the synthetic pending ticket',acceptError))
  callback(false,'Synthetic asynchronous refusal',ticket)
  callback(false,'Duplicate terminal refusal',ticket)
  C.guard(calls==1 and CB.VirtualStats().lastDataError==message,
   'ticket completion and duplicate notification respect the existing view hold')
 else
  C.setup(accepted and attempts==1,'public Share confirmation reaches synchronous refusal without throwing',acceptError)
  C.expect(calls==2 and (persistent and CB.VirtualStats().lastDataError==message
   and CB.VirtualStats().dataFailures==2 or not persistent and CB.VirtualStats().lastDataError==nil),
   'synchronous explicit Finish immediately attempts a contained refresh during hold',calls)
 end
 C.guard(#H.actions==actions and #H.sent==sent,
  'synthetic refused detail route submits no game or transport action')
 controller.PublishImportedBuild=publish;label.SetText=setter
 C.guard(Settle(H,CB)~=nil,'detail refusal control recovers through actual view publication')
end)
end
end

-- Explicit lock-in confirmation uses the real public popup, controller and
-- adapter with the unchanged synthetic harness host. Fake upload actions
-- are counted; no native server or transport operation is performed.
do
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
for _,arm in ipairs({'healthy','persistent-host-fault','spacing-pending','healthy-unheld'})do
C.scenario('lock-in-confirmation-'..arm,function()
 local H=F.Boot(F.Database(),function(h)
  h.playerLevel=60;h.perks.serverActiveSlot=1
  h.perks.serverBuildSlots={[1]={name='Synthetic lock-in proof',verified=true,echoes=L.OrdinaryRows(3)}}
 end)
 local CB=Nexus.CommunityBuilds
 C.setup(Nexus.StartupStatus().state=='ready'and not Nexus.Sync.IsReceiving(),'real TOC ready with actual Sync idle')
 CB.Show();local settled=false
 for _=1,2500 do
  H.Advance(.01,.01)
  if CB.DiagnosticSnapshot().projectionCurrent and not CB.VirtualStats().savedImport.pending then settled=true;break end
 end
 assert(C.setup(settled,'actual personal import and projection settle'))
 local mirror
 for _,b in pairs(CB.Builds())do if b.importedSavedBuild and b.serverSlot==1 then mirror=b end end
 assert(C.setup(mirror~=nil,'actual imported mirror is selectable'))
 CB.Select(mirror.id);H.Advance(3.1,.01)
 local upload=Nexus.GameAdapter.UploadWishlist;local pump=Nexus.ViewProjections.PumpBuilds
 local realHost=H.perks.UploadServerBuildSlot
 if arm=='spacing-pending'then
  CB.LockInSelected();local p=H.popup
  assert(C.setup(p and p.which=='NEXUS_LOCKIN_BUILD','public lock-in opens actual registered confirmation'))
  StaticPopupDialogs[p.which].OnAccept(p.frame,p.data)
  assert(C.setup(#H.actions==1 and H.actions[1][1]=='upload','one real adapter upload to unchanged synthetic host establishes spacing'))
 end
 local label=NexusCommunityBuildsFrame._classDropBtn;local setter=label.SetText
 local marker={label='Synthetic lock-in refresh exception'};local calls=0;local first=true
 label.SetText=function(self,...)
  calls=calls+1
  if arm~='healthy-unheld'and(first or arm=='persistent-host-fault')then first=false;error(marker,0)end
  return setter(self,...)
 end
 if arm~='healthy-unheld'then
  local failed,why=pcall(CB.Refresh)
  assert(C.setup(not failed and why==marker and calls==1 and CB.VirtualStats().dataFailures==1,
   'actual host exception establishes one retained view hold before user confirms'))
 else
  C.setup(calls==0 and CB.VirtualStats().dataFailures==0,'healthy explicit confirmation has no prior view hold')
 end
 CB.LockInSelected();local p=H.popup
 assert(C.setup(p and p.which=='NEXUS_LOCKIN_BUILD'and type(p.data.echoes)=='table',
  'public LockInSelected opens registered confirmation with real copied payload'))
 local beforeActions=#H.actions;local beforeAt=GetTime()
 local accepted,err=pcall(StaticPopupDialogs[p.which].OnAccept,p.frame,p.data)
 local stats=CB.VirtualStats()
 if arm=='spacing-pending'then
  C.guard(accepted and calls==1 and #H.actions==beforeActions and stats.dataFailures==1,
   'spacing refusal does not pretend success or bypass hold for a pending automatic retry')
 elseif arm=='healthy-unheld'then
  C.guard(accepted and #H.actions==beforeActions+1 and H.actions[#H.actions][1]=='upload'
   and stats.dataFailures==0 and calls>=1 and calls<=2,
   'healthy confirmation uploads once; explicit outcome may refresh after controller refresh')
  local uploads=#H.actions
  H.Advance(.2,.01)
  C.guard(#H.actions==uploads and CB.VirtualStats().lastDataError==nil,
   'healthy explicit confirmation starts no ongoing automatic upload loop')
 else
  C.setup(#H.actions==beforeActions+1 and H.actions[#H.actions][1]=='upload',
   'actual controller confirms one successful upload through real adapter to synthetic host')
  C.expect(calls==2 and GetTime()==beforeAt,
   'successful explicit confirmation refreshes immediately inside existing hold',calls)
  if arm=='persistent-host-fault'then
   C.expect(not accepted and err==marker and stats.dataFailures==2,
    'explicit post-success refresh retains and rethrows exact host exception')
  else
   C.expect(accepted and stats.lastDataError==nil and CB.DiagnosticSnapshot().projectionCurrent,
    'successful explicit refresh publishes and clears actual retained view error')
  end
 end
 C.guard(Nexus.GameAdapter.UploadWishlist==upload and Nexus.ViewProjections.PumpBuilds==pump
  and H.perks.UploadServerBuildSlot==realHost,'controller adapter/projection/host function identities preserved')
 C.guard(#H.sent==0,'synthetic proof sends no transport messages',#H.sent)
 label.SetText=setter
 print('OBSERVED_LOCKIN',arm,F.Serialize({calls=calls,accepted=accepted,
  exactError=err==marker,dataFailures=stats.dataFailures,syntheticHostUploads=#H.actions,
  sent=#H.sent,at=GetTime(),native='NOT_RUN'}))
end)
end
end

C.finish('(public failure hold and recovery; synthetic host only)')
