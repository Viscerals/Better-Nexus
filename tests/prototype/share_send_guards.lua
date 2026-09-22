-- NATIVE06 boundary checks through the actual retained Share lifecycle.
local S=dofile('tests/prototype/share_test_support.lua');local T=S.T
T.SingleSlicePacing()
local function Queued()
 local H,C=S.Boot();S.Incoming(H,C);H.combat=true;local first=S.Post('NEXUS-TEST-SEND-GUARDS');local id=first.id
 T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localSaved end)
 assert(Nexus.Sync.GetShareStatus(id).queueAdmitted and not Nexus.Sync.GetShareStatus(id).sendCompleted)
 local row=H.Clone((C.Get('synthetic-startup-2')));row.title='Later incoming';row.lastModified=3
 local ok,why,ticket=C.Put(row,{source='sync'})
 assert(ok==nil and why=='ROOT_MUTATION_PENDING' and ticket)
 H.combat=false
 return H,C,id,ticket
end
for _,guard in ipairs({'combat','bandwidth','CTL missing','suspended','adapter','owner','database','binding'})do
 local H,C,id=Queued();local before=#H.sent;local restore
 if guard=='combat' then H.combat=true;restore=function()H.combat=false end
 elseif guard=='bandwidth' then local ctl=Nexus.ChatThrottleLib;local old=ctl.UpdateAvail;ctl.UpdateAvail=function()return 0 end;restore=function()ctl.UpdateAvail=old end
 elseif guard=='CTL missing' then local ctl=Nexus.ChatThrottleLib;Nexus.ChatThrottleLib=nil;restore=function()Nexus.ChatThrottleLib=ctl end
 elseif guard=='suspended' then Nexus.SyncWire.suspended=true;restore=function()Nexus.SyncWire.suspended=false end
 elseif guard=='adapter' then local old=Nexus.GameAdapter.Ready;Nexus.GameAdapter.Ready=function()return false end;restore=function()Nexus.GameAdapter.Ready=old end
 elseif guard=='owner' then local old=UnitName;UnitName=function()return 'DifferentPlayer','Ebonhold' end;restore=function()UnitName=old end
 elseif guard=='database' then local db=NexusDB;NexusDB=H.Clone(db);restore=function()NexusDB=db end
 else C.BeginRootAdmission(NexusDB,Nexus.BundledBuilds) end
 H.Advance(8,.05)
 local status=Nexus.CommunityBuilds.ShareStatus(id)
 assert(not status.sendCompleted and status.attemptedAt==nil and #H.sent==before,guard..' blocks early dispatch')
 assert(status.localSaved and status.queueAdmitted,guard..' retains local save and admission history')
 if guard=='owner' or guard=='database' or guard=='binding' then
  assert(status.terminal and status.outcome=='superseded' and status.reason=='player or catalog changed',guard..' invalidates the original approval explicitly')
 else assert(not status.terminal,guard..' retains the admitted operation')end
 -- Owner/database/rebind changes invoke the real authority lifecycle. They
 -- must rebuild normally; do not force readiness or replace their candidate.
 if restore and guard~='owner' and guard~='database' then
  restore();H.Advance(8,.05)
  assert(not C.ManualPreparationStatus().ready,'real catalog work still pending after guard clears')
  assert(Nexus.Sync.GetShareStatus(id).sendCompleted and #H.sent==before+1,guard..' release sends the same packet once')
 end
 assert(H.putCalls[id]==1 and #H.shareCalls==1 and #H.actions==0,guard..' creates no replacement Share or gameplay action')
 print('PASS prepared Share guard '..guard)
end
-- A genuine wire block still expires at the original deadline. The normal UI
-- exposes an explicit retry only after terminal failure; no automatic replay.
local H,C,id,ticket=Queued();local initial=Nexus.Sync.GetShareStatus(id);local before=#H.sent
H.combat=true;H.Advance(119,.05)
assert(not Nexus.Sync.GetShareStatus(id).terminal,'original admission remains pending before expiry')
H.Advance(2,.05)
local failed=Nexus.CommunityBuilds.ShareStatus(id)
assert(failed.outcome=='expired' and failed.terminal and failed.reason=='expired' and failed.sendState=='expired','public receipt reports terminal unsent expiry')
assert(failed.resolvedAt-initial.queuedAt>=120 and failed.resolvedAt-initial.queuedAt<120.1,'deadline is unchanged; no blanket extension')
assert(failed.localSaved and failed.queueAdmitted and failed.queueReason=='queued','local save and historical admission remain truthful')
assert(not failed.sent and not failed.sendCompleted and not failed.attemptedAt and not failed.sentAt and #H.sent==before,'expiry cannot be reported as a send')
assert(failed.confirmation=='unavailable' and failed.peerStored==nil,'no invented peer confirmation')
T.Until(H,function()return ticket.committed and C.ManualPreparationStatus().ready end)
Nexus.CommunityBuilds.ShowBuild(id)
local retry
T.Until(H,function()
 for _,frame in ipairs(H.frames)do
  if frame:GetText()=='Retry Share' and frame:IsVisible() and frame:IsEnabled() then retry=frame;return true end
 end
end)
assert(retry and C.Get(id),'actual owned-build detail offers explicit Retry Share and retains the saved record')
H.combat=false;H.Advance(8,.05)
assert(Nexus.Sync.GetShareStatus(id).generation==initial.generation and Nexus.Sync.GetShareStatus(id).outcome=='expired','normal readiness never replaces the expired operation')
assert(H.putCalls[id]==1 and #H.shareCalls==1 and #H.actions==0,'expiry and UI refresh do not automatically retry or spend')
print('PASS original 120-second expiry, truthful public receipt and actual explicit Retry Share control; no automatic duplicate')
