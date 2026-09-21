-- Synthetic setup for bounded Share admission regressions.
local T=dofile('tests/prototype/startup_support.lua')
local S={T=T}
function S.Boot()
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/harness.lua')
 NexusDB=T.Profile(100,0)
 H.perks.serverBuildSlots={[102]={name='NEXUS-TEST-SHARE-GUARDS',verified=false,
  echoes={{spellId=200001,quality=1,stacks=3}}}}
 T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
 local C=Nexus.BuildCatalog
 T.Until(H,function()return C.ManualPreparationStatus().ready end)
 H.shareCalls={};H.putCalls={}
 local broadcast=Nexus.Sync.BroadcastBuildSummary
 Nexus.Sync.BroadcastBuildSummary=function(record,...)
  H.shareCalls[#H.shareCalls+1]=H.Clone(record);return broadcast(record,...)
 end
 local put=C.Put
 C.Put=function(record,...)
  H.putCalls[record.id]=(H.putCalls[record.id] or 0)+1;return put(record,...)
 end
 return H,C
end
function S.Incoming(H,C)
 local record=H.Clone((C.Get('synthetic-startup-1')))
 record.title='Incoming contention';record.lastModified=2
 local ok,why,ticket=C.Put(record,{source='sync'})
 assert(ok==nil and why=='ROOT_MUTATION_PENDING' and ticket,'real pending incoming write')
 return ticket
end
function S.Post(title)
 Nexus.CommunityBuilds.ShowPostBuild()
 local p=assert(NexusPostPopup)
 assert(p:IsVisible() and p._postGoBtn:IsVisible() and p._postGoBtn:IsEnabled(),'actual Share controls visible/enabled')
 p._postTitleBox:_NexusSetRawText(title or 'NEXUS-TEST-SHARE-GUARDS')
 p._postDescBox:_NexusSetRawText('Approved immutable test description')
 p._postGoBtn:Click()
 return assert(Nexus.CommunityBuilds.ShareStatus()),p
end
return S
