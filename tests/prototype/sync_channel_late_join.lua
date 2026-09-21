-- A temporary channel join is asynchronous on a real client: the channel is
-- listed a moment after the addon's join call. The join retry runs only in the
-- full Sync turn, and every hold and yield of the deferred admission owner
-- requires IsConnected. Under inbound traffic the catalog stays busy, no full
-- turn accumulates, and the client stayed unconnected for the whole session.
-- Channel traffic now reconciles the channel index passively. This restores
-- connection, hold and yield eligibility only; it does not change the cost of
-- one inbound record. Real TOC, lifecycle, adapter, Sync, session, catalog and
-- transport; only the game channel API is modelled. Synthetic data only.
local T=dofile('tests/prototype/startup_support.lua')
local H,C,listing,joinCalls,ensureCalls,turns,handled
-- listing: nil = nothing listed, otherwise {index,name,index,name,...}
local function Boot(rows,async)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 H=dofile('tests/prototype/harness.lua')
 joinCalls,ensureCalls,turns,handled=0,0,0,0
 local pendingAt
 listing=not async and {1,'wrbuildssync'} or nil
 JoinTemporaryChannel=function(name)joinCalls=joinCalls+1;if async and not listing then pendingAt=pendingAt or H.now+.5 end end
 JoinChannelByName=JoinTemporaryChannel
 GetChannelList=function()
  if not listing and pendingAt and H.now>=pendingAt then listing={1,'wrbuildssync'} end
  if listing then return unpack(listing) end
 end
 GetChannelName=function()local i,n=GetChannelList();return i or 0,n end
 NexusDB=T.Profile(rows,0)
 T.Load()
 local update=Nexus.Sync.OnUpdate;Nexus.Sync.OnUpdate=function(...)turns=turns+1;return update(...)end
 local ensure=Nexus.Sync.EnsureChannel;Nexus.Sync.EnsureChannel=function(...)ensureCalls=ensureCalls+1;return ensure(...)end
 local incoming=Nexus.Sync.HandleIncoming;Nexus.Sync.HandleIncoming=function(...)handled=handled+1;return incoming(...)end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H,function()return Nexus.StartupStatus().state=='ready' end)
 C=Nexus.BuildCatalog
end
local arrivals=0
local function Wire()
 arrivals=arrivals+1
 local owner='LateJoin'..((arrivals-1)%8+1)
 local d={id='late-join-'..arrivals,t='Synthetic late join traffic '..arrivals,a=owner..'-Ebonhold',
  o=Nexus.Identity.OwnerKey(owner,'Ebonhold'),c='MAGE',m=time()+arrivals,h='a1',n=3}
 return 'WLBI|'..d.a..'|'..Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode(d)),d.a,d.id
end
-- The real channel event, as the game delivers it: numbered and bare channel name.
local function Channel(name,text,sender)H.Fire('CHAT_MSG_CHANNEL',text,sender,nil,'1. '..name,nil,nil,nil,nil,name)end
local function Arrive()local text,sender,id=Wire();Channel(Nexus.Sync.ChannelName(),text,sender);return id end
local function ChannelSends()local n=0;for _,p in ipairs(H.sent)do if p.kind=='CHANNEL' then n=n+1 end end;return n end

-- A valid ordinary request text for the owed-work case, from a client whose
-- channel is listed at once (the harness default every other test uses).
Boot(5,false)
assert(Nexus.Sync.IsConnected() and joinCalls==0,'control: a channel that is listed at once connects at Sync start without a join call')
T.Until(H,function()return Nexus.StartupStatus().syncGate=='open' end,20000)
SlashCmdList.NEXUS('sync')
local requestText
T.Until(H,function()for _,p in ipairs(H.sent)do local s=p.text:gsub('||','|'):gsub('^P%d+:','');if s:find('^WLRQ|')then requestText=s end end;return requestText~=nil end,4000)

-- 1. Quiet channel: the existing join retry connects, unchanged, with one join call.
Boot(5,true)
assert(not Nexus.Sync.IsConnected() and joinCalls==1,'fixture: the join call was made and the channel was not listed in the same call')
T.Until(H,function()return Nexus.Sync.IsConnected()end,4000)
assert(turns>=200 and ensureCalls>=1 and handled==0 and joinCalls==1,'quiet: connected through the unchanged retry after ten seconds of full turns, without a second join')
print(string.format('PASS quiet channel: existing retry connected after %d full turns, 1 join call',turns))

-- 2. Traffic: the first channel message reconciles the index at once. No join,
-- no send, no retry call and no full turn is needed for it.
Boot(40,true)
H.Advance(.6,.05)                                        -- the game now lists the channel
assert(GetChannelList()==1 and not Nexus.Sync.IsConnected(),'fixture: joined in the game, still unconnected in the addon')
local before={joins=joinCalls,ensures=ensureCalls,turns=turns,sent=#H.sent}
Arrive()
assert(Nexus.Sync.IsConnected() and Nexus.Sync.ChannelIndex()==1,'the first channel message reconciles the channel index the game lists')
assert(joinCalls==before.joins and ensureCalls==before.ensures and turns==before.turns and #H.sent==before.sent,'passive: no join call, no EnsureChannel, no full turn and no send came from the reconciliation')
assert(handled==1,'fixture: the message went through the real lifecycle route')
-- One valid record every second keeps the catalog busy. The client stays connected.
for i=1,1200 do if i%20==0 then Arrive()end;H.Advance(.05,.05)end
assert(Nexus.Sync.IsConnected() and joinCalls==before.joins,'sustained traffic: still connected, still no further join call')
assert(Nexus.Sync.Stats().malformedRejected==0,'valid items stay valid')
print(string.format('PASS async join under traffic: connected by the first channel message with %d joins, %d sends and %d full turns from it',joinCalls-before.joins,0,0))

-- 3. Holds apply when work is owed. They require IsConnected, so on an
-- unconnected client the next arrival took the catalog instead.
T.Until(H,function()local w=Nexus.Sync.WorkState();return C.ManualPreparationStatus().ready and w.deferredAdmissions==0 and w.recovery==0 and w.outbound==0 and w.pendingResponses==0 end,40000)
local peerRequest=requestText:gsub('^WLRQ|[^|]+|','WLRQ|LatePeer|'):gsub('c1%-[%w%-]+','c1-7001-1001')
Channel(Nexus.Sync.ChannelName(),peerRequest,'LatePeer-Ebonhold')
assert(Nexus.Sync.WorkState().pendingResponses==1,'fixture: one peer request is pending')
local held=Nexus.Sync.Stats().admissionHeld or 0
Arrive()
assert((Nexus.Sync.Stats().admissionHeld or 0)==held+1 and C.ManualPreparationStatus().ready,'a valid arrival is retained while a response is owed; it does not take the catalog')
print('PASS holds apply when owed on the reconciled connection')

-- 4. Wrong channel. A message on another channel never reaches Sync and never
-- connects. Without a listed Sync channel nothing claims a connection either.
Boot(5,true)
H.Advance(.6,.05)
assert(GetChannelList()==1 and not Nexus.Sync.IsConnected())
local text,sender=Wire()
Channel('General',text,sender)
assert(handled==0 and not Nexus.Sync.IsConnected(),'a message on another channel is not routed to Sync and reconciles nothing')
listing={1,'General'}                                   -- the game lists other channels only
assert(Nexus.Sync.NoteChannelTraffic()==false and not Nexus.Sync.IsConnected(),'no connection is reported that the game does not list')
listing={1,'General',3,'wrbuildssync'}
Arrive()
assert(Nexus.Sync.IsConnected() and Nexus.Sync.ChannelIndex()==3,'the slot recorded is the Sync channel\'s own, not another channel\'s')
print('PASS wrong-channel isolation')

-- 5. Moved or stale slot. The reconciliation never rewrites a known index;
-- every send still resolves its slot at send time and never goes to the old one.
local real=SendChatMessage
SendChatMessage=function(message,kind,language,target)
 if kind=='CHANNEL' then
  local listed;for i=1,#listing,2 do if listing[i+1]=='wrbuildssync' then listed=listing[i] end end
  assert(target==listed,'a channel send goes to the slot the game lists at that moment: '..tostring(target)..' vs '..tostring(listed))
 end
 return real(message,kind,language,target)
end
listing={1,'General',2,'Trade',5,'wrbuildssync'}        -- the channel moved from 3 to 5
Arrive()
assert(Nexus.Sync.ChannelIndex()==3,'traffic does not rewrite a known index')
T.Until(H,function()return Nexus.StartupStatus().syncGate=='open' end,40000)
local sends=ChannelSends()
SlashCmdList.NEXUS('sync')
T.Until(H,function()return ChannelSends()>sends end,8000)
assert(Nexus.Sync.ChannelIndex()==5,'the send resolved the moved slot')
for _,p in ipairs(H.sent)do assert(p.kind~='CHANNEL' or p.target~=1 and p.target~=2,'nothing was sent to General or Trade')end
assert(#H.actions==0,'zero gameplay mutation')
print('PASS moved slot: send-time resolution unchanged, nothing sent to another channel')
