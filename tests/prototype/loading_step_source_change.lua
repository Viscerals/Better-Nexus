-- A real catalog update arrives during the Community scan. The scan position
-- belongs to a cursor that the new root replaces, so the loading window must
-- not show it again: during the catalog work it shows the catalog step, and
-- the Community step shows a count again only after Community reports anew.
-- Synthetic profile; real startup, catalog Put and loading window.
local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(80,40);T.Load()
debugprofilestop=nil
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local reports,base=0,Nexus.CommunityBuilds.Init
Nexus.CommunityBuilds.Init=function(...)local r=base(...);reports=reports+1;return r end
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
SlashCmdList.NEXUS('loading')
local f,L=NexusLoadingStatusFrame,Nexus.LoadingStatus
T.Until(H,function()local s=Nexus.StartupStatus();return s.step=='scan' and (s.stepDone or 0)>=2 end)
local old=Nexus.StartupStatus()
check(old.stepTotal==80,'scan counts the root rows before the update')
local changed=H.Clone(NexusDB.authorityBundle.communityBuilds['synthetic-startup-1'])
changed.title='Updated during preparation'
local put,reason=Nexus.BuildCatalog.Put(changed,{source='sync'})
check(put==true or put==nil and reason=='ROOT_MUTATION_PENDING','real catalog update accepted: '..tostring(reason))
local catalogTurns,afterReport,reportsAtPut=0,0,reports
for i=1,20000 do
 H.Advance(.05,.05);L.Update(nil,true)
 local s=Nexus.StartupStatus();local text=f.detail:GetText()
 if s.state=='ready' then break end
 if s.step:sub(1,8)=='catalog-' then
  catalogTurns=catalogTurns+1
  check(Nexus.startupTiming.communityProgressDone==nil,'the replaced scan position is cleared while catalog work runs')
  -- The count is cleared whenever catalog work holds Community back; this
  -- check covers the replaced-scan case, the only step that shows the count.
  check(Nexus.startupTiming.communityPhase~='scan' or Nexus.startupTiming.communityRecordsSeen==nil,'the replaced scan record count is cleared while catalog work runs')
  check(not text:find(' / 80 ',1,true) or s.stepTotal==80,'no scan count is shown for catalog work: '..text)
 elseif s.step=='scan' and s.stepDone then
  afterReport=afterReport+1
  check(reports>reportsAtPut,'a scan count after the update comes from a new Community report')
 end
end
check(catalogTurns>0,'the catalog update was observed as a catalog step')
check(Nexus.StartupStatus().state=='ready','startup still completes through its owner')
check(NexusDB.authorityBundle.communityBuilds['synthetic-startup-1'].title=='Updated during preparation','the update is kept')
print('PASS loading_step_source_change: catalogTurns='..catalogTurns..' rescans='..afterReport..' checks='..checks)
