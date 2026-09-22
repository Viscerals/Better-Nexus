-- Actual Share popup/controller while a real catalog write owns admission.
-- Synthetic incoming records and network only; no game or live saved data.
local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(100,0)
H.perks.serverActiveSlot=0
H.perks.serverBuildSlots={[102]={name='NEXUS-TEST-SHARE-CONTENTION',verified=false,
 echoes={{spellId=200001,quality=1,stacks=3}}}}
T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
T.Until(H,function()return Nexus.BuildCatalog.ManualPreparationStatus().ready end)
local C=Nexus.BuildCatalog
local before=H.Clone(H.perks.serverBuildSlots)
local put=C.Put;local puts={}
C.Put=function(record,...)
 puts[record.id]=(puts[record.id] or 0)+1
 return put(record,...)
end
-- A record committed inside a receiver batch is recorded exactly like a
-- single put, so the counts below keep their meaning on both routes.
local putBatch=C.PutBatch
if type(putBatch)=='function' then
 C.PutBatch=function(requests,...)
  for _,request in ipairs(requests or {})do
   local record=type(request)=='table' and request.record or nil
   if record then puts[record.id]=(puts[record.id] or 0)+1 end
  end
  return putBatch(requests,...)
 end
end
local broadcast=Nexus.Sync.BroadcastBuildSummary
local shares={}
Nexus.Sync.BroadcastBuildSummary=function(record,...)
 shares[#shares+1]=H.Clone(record)
 return broadcast(record,...)
end
Nexus.CommunityBuilds.ShowPostBuild()
local p=assert(NexusPostPopup)
assert(p:IsVisible(),'actual Share popup opens')
p._postTitleBox:_NexusSetRawText('NEXUS-TEST-SHARE-CONTENTION')
p._postDescBox:_NexusSetRawText('Synthetic contention regression')
local incoming=H.Clone((C.Get('synthetic-startup-1')))
assert(incoming,'real admitted incoming-record fixture')
incoming.title='Incoming update during Share';incoming.lastModified=2
local ok,why,ticket=C.Put(incoming,{source='sync'})
assert(ok==nil and why=='ROOT_MUTATION_PENDING' and ticket,'real incoming update must hold a retained catalog ticket')
local busy=C.ManualPreparationStatus()
assert(not busy.ready and busy.ownerAgrees,'real same-owner catalog work is pending')
print('SHARE_BUSY',busy.reason,busy.kind,busy.phase,busy.pumps,busy.work)
assert(p._postGoBtn:IsVisible() and p._postGoBtn:IsEnabled(),'normal Share control is usable before submission')
p._postGoBtn:Click()
local outcome=assert(Nexus.CommunityBuilds.ShareStatus(),'actual Share attempt produces status')
local id=assert(outcome.id)
print('SHARE_ATTEMPT',id,outcome.localSaved,outcome.queueAdmitted,outcome.queueReason,p:IsShown())
assert(not outcome.localSaved and not outcome.queueAdmitted and #shares==0,'pending admission must not claim a save or queue a broadcast')
assert(C.Get(id)==nil and Nexus.Sync.GetShareStatus(id)==nil,'pending admission has no published record or send receipt')
assert(outcome.localPending and outcome.localStage=='waiting-catalog' and not p:IsShown(),'accepted intent reports waiting and closes the submitted form')
assert(not puts[id],'busy admission has not submitted the approved record')
for i=1,4 do
 local status=Nexus.CommunityBuilds.ShareStatus(id)
 assert(status.id==id and status.localPending and not puts[id],'status reads cannot submit or allocate another record')
end
-- Reopening and clicking cannot replace the outstanding approved intent.
Nexus.CommunityBuilds.ShowPostBuild()
p._postTitleBox:_NexusSetRawText('A different later draft')
assert(p._postGoBtn:IsVisible() and p._postGoBtn:IsEnabled())
p._postGoBtn:Click()
assert(p:IsShown() and Nexus.CommunityBuilds.ShareStatus().id==id,'duplicate pending submission keeps the one original ID')
Nexus.CommunityBuilds.ShowPostBuild()
T.Until(H,function()return C.ManualPreparationStatus().ready end)
assert(ticket.committed and C.Get('synthetic-startup-1').title==incoming.title,'original incoming update settles without bypassing its guard')
T.Until(H,function()
 local state=Nexus.CommunityBuilds.ShareStatus(id)
 return C.ManualPreparationStatus().ready and (state.localSaved or H.now>1400)
end)
local record=C.Get(id)
assert(record,'NATIVE-05: one approved Share must survive incoming catalog work and save without another click')
assert(record.title=='NEXUS-TEST-SHARE-CONTENTION' and record.description=='Synthetic contention regression','saved record retains the exact approved metadata')
assert(record.class=='MAGE' and #record.echoes==1 and record.echoes[1].spellId==200001 and record.echoes[1].quality==1 and record.echoes[1].stacks==3,'saved record retains the exact approved Echo source')
assert(#shares==1 and shares[1].id==id,'exactly one broadcast follows confirmed local save of the same ID')
assert(puts[id]==1,'one approved intent causes one local submission, without blind retries')
local final=Nexus.CommunityBuilds.ShareStatus(id)
assert(final.localSaved and final.queueAdmitted,'normal transport admission is reported after local commit')
assert(T.Equal(before,H.perks.serverBuildSlots),'Share never changes server Wishlists or active loadout')
assert(#H.actions==0,'Share causes no gameplay or server-source mutation')
local orb=Nexus.OrbRuntime.Status()
assert(not orb.running and not orb.pending and orb.spent==0 and orb.reserved==0,'Share creates no Orb exposure')
print('PASS actual Share intent survives unrelated incoming catalog work, one exact record and one broadcast, no gameplay mutation')
