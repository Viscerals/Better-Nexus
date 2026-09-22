local E=dofile('tests/prototype/share_edit_support.lua');local T=E.T
T.SingleSlicePacing()
for _,phase in ipairs({'saving','queued'})do
 for _,change in ipairs({'owner','database','binding'})do
  local H,C,id,p,old=E.Begin();local restore=E.CapturePrint(H)
  local before=E.Submit(H,C,id,p,old);restore()
  local revision
  if phase=='queued' then revision=E.AwaitCommit(H,C,id,old).lastModified end
  if change=='owner' then UnitName=function()return 'DifferentPlayer','Ebonhold' end
  elseif change=='database' then NexusDB=H.Clone(NexusDB)
  else C.BeginRootAdmission(NexusDB,Nexus.BundledBuilds)end
  H.combat=false;H.Advance(160,.05)
  if phase=='saving' then
   assert(#H.shareCalls==before.broadcasts,'invalidated '..change..' cannot broadcast a pending Edit')
  else
   local status=Nexus.Sync.GetShareStatus(id)
   assert(status.terminal and status.outcome=='superseded' and status.reason=='player or catalog changed','queued Edit publishes the exact invalidation reason')
   assert(not status.attemptedAt and not status.sentAt and not status.sendCompleted and #E.Sends(H,id,revision)==0,'invalidated admitted Edit never sends')
   assert(#H.shareCalls==before.broadcasts+1,'invalidated admitted Edit has no replacement broadcast')
  end
  assert(H.putCalls[id]==before.puts+1 and #H.actions==0,'scope change neither resubmits nor spends')
  print('PASS Edit '..phase..' invalidation on '..change)
 end
end
local H,C,id,p,old=E.Begin();local restore=E.CapturePrint(H)
local before=E.Submit(H,C,id,p,old);restore();local updated=E.AwaitCommit(H,C,id,old)
local status=Nexus.Sync.GetShareStatus(id);H.Advance(121,.05)
local expired=Nexus.Sync.GetShareStatus(id)
assert(expired.terminal and expired.outcome=='expired' and expired.reason=='expired' and not expired.sendCompleted and not expired.attemptedAt,'combat-blocked Edit expires honestly before any attempt')
assert(expired.resolvedAt-status.queuedAt>=120 and expired.resolvedAt-status.queuedAt<120.1,'explicit Edit does not extend the Share expiry')
H.combat=false;H.Advance(10,.05)
assert(#E.Sends(H,id,updated.lastModified)==0 and #H.shareCalls==before.broadcasts+1 and H.putCalls[id]==before.puts+1,'expiry never creates an automatic Edit retry')
assert(#H.actions==0,'combat expiry makes no gameplay action')
print('PASS Edit combat expiry retains the saved exact record and original terminal operation without retry')
-- Busy admission returns no ticket. It must not be presented as accepted.
H,C,id,p,old=E.Begin();local ticket=E.LaterWork(H,C,'put')
local count=#H.shareCalls;restore=E.CapturePrint(H);p._saveBtn:Click();restore()
assert(p:IsShown() and H.editPrint:find('ROOT_MUTATION_PENDING',1,true),'actual Edit form reports refused busy admission and remains open')
assert(C.Get(id).lastModified==old.lastModified and #H.shareCalls==count,'unadmitted Edit has no saved revision or broadcast')
H.Advance(8,.05)
assert(not ticket.committed and #H.shareCalls==count and #H.actions==0,'foreign catalog work is preserved without automatic resubmission')
print('PASS Edit refuses foreign pending admission truthfully; no false accepted ticket or hidden retry')
