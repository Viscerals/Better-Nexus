-- Saved Sync mode Manual: a Share whose first admission meets a full queue is
-- admitted later by the existing bounded retry. It must keep the same
-- follow-up permission as a first-time admission: a peer fetching that record
-- is answered. The full queue is one injected "sync queue full" at the real
-- transport admission (not a send flag). Real TOC boot, Share controls,
-- transport and wire; the peer's fetch is a real inbound channel message.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local injected=0
F.fileHooks={['core\\SyncTransport.lua']=function()
 local factory=Nexus.SyncInternals.Transport
 local New=factory.New
 factory.New=function(...)
  local T=New(...)
  local enqueue=T.EnqueueControl
  T.EnqueueControl=function(payload,metadata)
   if injected==0 and type(metadata)=='table' and metadata.queueClass=='share' then
    injected=1;return false,'sync queue full'
   end
   return enqueue(payload,metadata)
  end
  return T
 end
end}
local db=F.Database({mutate=function(d)d.settings.syncMode='manual';d.communityBuilds={};d.chars={} end})
local H=F.Boot(db,function(H)
 H.perks.serverBuildSlots={[102]={name='NEXUS-TEST-RETRY',verified=false,echoes={{spellId=200001,quality=1,stacks=3}}}}
end)
F.fileHooks=nil
check(Nexus.SyncModePolicy.Mode()=='manual','fixture: accepted format 5 with Manual')
for i=1,400 do H.Advance(.05,.05) if Nexus.BuildCatalog.ManualPreparationStatus().ready then break end end
Nexus.CommunityBuilds.ShowPostBuild()
local p=assert(NexusPostPopup)
p._postTitleBox:_NexusSetRawText('NEXUS-TEST-RETRY-SHARE')
p._postDescBox:_NexusSetRawText('Synthetic retry share')
p._postGoBtn:Click()
local id=assert(Nexus.CommunityBuilds.ShareStatus()).id
local summary=false
for i=1,3000 do
 H.Advance(.05,.05)
 for _,s in ipairs(H.sent)do if s.text:find('^WLBI') then summary=true end end
 if summary then break end
end
check(injected==1,'the first Share admission met a full queue')
check(summary,'the bounded retry admitted and sent the Share summary under Manual')
-- A peer fetches the shared record's Echo list: it must be answered.
local before=#H.sent
local channel=Nexus.Sync.ChannelName()
H.Fire('CHAT_MSG_CHANNEL','WLLQ|Fetcher|'..id,'Fetcher-Ebonhold',nil,'1. '..channel,nil,nil,nil,nil,channel)
local answered=false
for i=1,600 do
 H.Advance(.05,.05)
 for k=before+1,#H.sent do if H.sent[k].text:find(id,1,true) then answered=true end end
 if answered then break end
end
check(answered,'Manual: the retry-admitted Share answers the peer fetching that record')
print('PASS sync_saved_mode_share_retry: retry-admitted Share keeps its follow-up permission under Manual checks='..checks)
