local S=dofile('tests/prototype/share_test_support.lua');local T=S.T
for _,change in ipairs({'owner','database','binding'})do
 local H,C=S.Boot();S.Incoming(H,C)
 local status=S.Post();local id=status.id
 assert(status.localPending and not H.putCalls[id],'one waiting Share retained before local submission')
 if change=='owner' then UnitName=function()return 'DifferentPlayer','Ebonhold' end
 elseif change=='database' then NexusDB=H.Clone(NexusDB)
 else C.BeginRootAdmission(NexusDB,Nexus.BundledBuilds) end
 -- The existing lifecycle owns this boundary; the controller must not move an
 -- approved intent to another owner/database or manufacture a local commit.
 Nexus.CommunityBuilds.PumpPendingShare()
 status=Nexus.CommunityBuilds.ShareStatus(id)
 assert(not status.localPending and not status.localSaved and not status.queueAdmitted,'scope change terminates an unsubmitted intent')
 assert(status.queueReason:find('player or catalog changed',1,true),'scope cancellation has a specific reason')
 for i=1,3 do Nexus.CommunityBuilds.PumpPendingShare()end
 assert(not H.putCalls[id] and #H.shareCalls==0,'cancelled intent cannot submit or broadcast on later pumps')
 assert(#H.actions==0,'scope guards perform no gameplay action')
 print('PASS waiting Share cancellation on '..change..' change')
end
-- Retain one submitted ticket through a real catalog cancellation. Do not retry.
local H,C=S.Boot();S.Incoming(H,C);local first=S.Post();local id=first.id
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localStage=='saving' end)
local saving=Nexus.CommunityBuilds.ShareStatus(id)
assert(saving.localPending and not saving.localSaved and H.putCalls[id]==1,'one accepted local ticket remains pending')
assert(C.Get(id)==nil and #H.shareCalls==0,'a retained ticket is not a committed record or broadcast')
C.CancelRootAdmission()
local failed=Nexus.CommunityBuilds.ShareStatus(id)
assert(not failed.localPending and not failed.localSaved and not failed.queueAdmitted,'real cancelled ticket cannot report success')
assert(failed.queueReason=='CANCELLED','retain the actual terminal ticket failure reason')
for i=1,5 do Nexus.CommunityBuilds.PumpPendingShare()end
assert(H.putCalls[id]==1 and #H.shareCalls==0 and Nexus.Sync.GetShareStatus(id)==nil,'failed ticket has no automatic resubmission or send')
assert(#H.actions==0,'failure settlement makes no gameplay call')
print('PASS real failed local ticket settles once, without retry, send or false success')
-- A ticket may commit to its original database after player identity changes.
-- That fact is retained, but the old approved record must not be broadcast.
H,C=S.Boot();S.Incoming(H,C);first=S.Post();id=first.id
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localStage=='saving' end)
UnitName=function()return 'DifferentPlayer','Ebonhold' end
T.Until(H,function()return not Nexus.CommunityBuilds.ShareStatus(id).localPending end)
local changed=Nexus.CommunityBuilds.ShareStatus(id)
assert(not changed.queueAdmitted and #H.shareCalls==0 and H.putCalls[id]==1,'owner change after submission cannot send or duplicate the approved record')
assert(changed.queueReason:find('player or catalog changed',1,true),'post-commit owner mismatch has a specific reason')
assert(#H.actions==0,'post-submission owner change makes no gameplay call')
print('PASS owner change after actual local submission prevents broadcast')
-- A change to the source mirror or another form after approval cannot rewrite it.
H,C=S.Boot();S.Incoming(H,C);first=S.Post();id=first.id
H.perks.serverBuildSlots[102].echoes[1].stacks=4
H.perks.serverBuildSlots[102].name='Later source name'
H.Notify();Nexus.GameAdapter.Poll()
T.Until(H,function()return Nexus.CommunityBuilds.ShareStatus(id).localSaved end)
local record=assert(C.Get(id))
assert(record.echoes[1].stacks==3 and record.title=='NEXUS-TEST-SHARE-GUARDS' and record.description=='Approved immutable test description','pending Share preserves the approved exact content snapshot')
assert(H.putCalls[id]==1 and #H.shareCalls==1 and H.shareCalls[1].id==id,'source changes cause no duplicate local record or broadcast')
assert(H.perks.serverBuildSlots[102].echoes[1].stacks==4 and #H.actions==0,'sharing does not replace or upload the changed source')
local orb=Nexus.OrbRuntime.Status()
assert(not orb.running and not orb.pending and orb.spent==0 and orb.reserved==0,'Share lifecycle keeps Orb mode idle')
print('PASS approved Share snapshot remains immutable across later source edits')
