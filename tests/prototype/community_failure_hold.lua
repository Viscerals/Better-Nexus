-- Real TOC, Community facade/controller/projection factory and registered frame.
-- Faults touch only public dependencies or synthetic host methods. No renderer,
-- List or PumpBuilds replacement; no native timing or global error-history claim.
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

C.finish('(public failure hold and recovery; synthetic host only)')
