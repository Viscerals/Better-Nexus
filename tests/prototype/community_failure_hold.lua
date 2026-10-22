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
local function Stack()
 local rows,callback,lifecycle,catalog={},false,false,false
 for i=2,50 do
  local info=debug.getinfo(i,'Sln')
  if not info then break end
  rows[#rows+1]=(info.source or '?')..':'..tostring(info.currentline)..' ('..(info.name or '?')..')'
  if info.source=='@core/CommunityController.lua' and info.currentline==129 then callback=true end
  if info.source=='@core/MainLifecycle.lua' then lifecycle=true end
  if info.source=='@core/BuildCatalog.lua' then catalog=true end
 end
 return table.concat(rows,'\n'),callback,lifecycle,catalog
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
local message='Synthetic Share status SetText fault before Library initialization'
popup._shareStatus.SetText=function(self,...)
 local trace,isCallback,isLifecycle,isCatalog=Stack()
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
  for _,f in ipairs(H.frames) do if f.lockBtn and f.lockBtn.GetText then detail=f end end
  if not C.setup(detail and detail:IsShown() and detail.lockBtn:IsShown()
   and detail.lockBtn:GetText()=='Share Build','real saved-mirror detail Share action is visible') then return end
  local commit=CAT.CommitMaintenance;local tickets={}
  CAT.CommitMaintenance=function(...)
   local ok,why,ticket=commit(...);if type(ticket)=='table' then tickets[#tickets+1]=ticket end
   return ok,why,ticket
  end
  local frame=NexusCommunityBuildsFrame;local setText=frame._classDropBtn.SetText;local faults={}
  if faulted then frame._classDropBtn.SetText=function()
   faults[#faults+1]={at=H.now,stack=debug.traceback('',2)};error('DETAIL_FINISH_VIEW_HOST_FAULT',0)
  end end
  local clicked,err=pcall(function() detail.lockBtn:Click() end)
  if not C.setup(clicked and #tickets==1 and tickets[1].state=='pending'
   and detail.lockBtn:GetText()=='Sharing...','real detail click queues one asynchronous publish ticket',err) then return end
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
 C.expect(CB.VirtualStats().dataFailures==#calls and CB.VirtualStats().lastDataError=='Persistent popup status host failure',
  'each actual popup exception is retained once in the view ledger',CB.VirtualStats().dataFailures)
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
  escaped=escaped,failures=CB.VirtualStats().dataFailures,restoredText=status:GetText(),puts=H.putCalls[id]}))
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

C.finish('(public failure hold and recovery; synthetic host only)')
