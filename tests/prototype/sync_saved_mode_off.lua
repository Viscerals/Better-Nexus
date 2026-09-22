-- Saved Sync mode Off (accepted format 5, Good Enough Nexus layout): zero
-- Nexus-generated outbound messages on every route, while a normal format-2
-- peer keeps syncing. Two real runtimes (sync_pair_support); the only packets
-- are those captured from real SendChatMessage/SendAddonMessage calls.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Format5(mode)return function(i,db)
 if i~=1 then return end
 db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode=mode
end end
local A,B=P.Boot({'OffPeer','AutoPeer'},{5,8},Format5('off'))
local function Sent(p)return #p.H.sent end
check(Sent(A)==0,'Off: nothing sent during start-up')
check(A.e.Nexus.SyncModePolicy.Mode()=='off','the accepted format-5 Off choice is honored')

-- The format-2 peer syncs automatically, asks A, and offers handshakes.
P.Advance(40)
check(Sent(B)>0,'fixture: the automatic peer sends requests')
B.e.Nexus.Sync.RequestSync();P.Advance(20)
B.H.Fire('CHAT_MSG_ADDON','NEXUS_P1','HELLO1','WHISPER','OffPeer-Ebonhold')
A.H.Fire('CHAT_MSG_ADDON','NEXUS_P1','HELLO1','WHISPER','AutoPeer-Ebonhold');P.Advance(10)
check(Sent(A)==0,'Off: no response, claim, handshake or login Sync after peer traffic: '..Sent(A))
check(A.e.Nexus.SyncWire.Stats().pendingHandshakes==0,'Off: no handshake accumulates behind the refusal')
check((A.e.Nexus.Sync.Stats().admittedPackets or 0)==0,'Off: no answer or request is even queued (no backlog behind the refusal)')

-- Sync Now (slash and the Build Library button) is refused with the reason.
local refusedBefore=A.e.Nexus.Sync.Stats().modeRefused or 0
local chat=#A.H.chat
A.e.SlashCmdList.NEXUS('sync');P.Advance(5)
local said=table.concat(A.H.chat,'\n',chat+1)
check(said:find('saved Sync mode is Off',1,true),'Off: /nexus sync explains the saved Off mode: '..said)
local ok,why=A.e.Nexus.Sync.RequestSync()
check(ok==false and tostring(why):find('saved Sync mode is Off',1,true),'Off: Sync Now refuses with the reason')
check((A.e.Nexus.Sync.Stats().modeRefused or 0)==refusedBefore,'Off: Sync Now is refused before any request is built or queued')
A.e.Nexus.CommunityBuilds.Show();P.Advance(1)
local status=A.e.NexusCommunityBuildsFrame and A.e.NexusCommunityBuildsFrame._syncStatusText
check(status and status:GetText():find('saved Sync mode is Off',1,true),'Off: the Build Library status states the saved mode')

-- An explicit Share keeps the local record, is not labelled Sent and is not left preparing.
local id=P.Post(A,'NEXUS-TEST-OFF-SHARE')
local firstKind,firstText=A.e.Nexus.CommunityBuilds.ShareStatusText(id)
check(firstKind=='preparing' and tostring(firstText):find('saved Sync mode is Off: it will be saved locally and not sent',1,true),
 'Off: while preparing, the Share already states it will not be sent: '..tostring(firstKind)..' '..tostring(firstText))
P.Advance(10)
local kind,text=A.e.Nexus.CommunityBuilds.ShareStatusText(id)
check(kind=='stopped','Off: the Share ends stopped, not sent, queued or preparing: '..tostring(kind))
check(tostring(text):find('saved Sync mode is Off',1,true) and tostring(text):find('locally',1,true),
 'Off: the Share states it is saved locally and the saved Off mode: '..tostring(text))
local share=A.e.Nexus.CommunityBuilds.ShareStatus(id)
check(share and share.sendCompleted~=true and share.terminal==true,'Off: the Share operation is terminal and never marked sent')
check(A.e.Nexus.BuildCatalog.Get(id)~=nil,'Off: the shared record is kept locally')
check((A.e.Nexus.Sync.Stats().admittedPackets or 0)==0,'Off: the Share is refused at queue admission; nothing waits in the queue')

-- The diagnostic probe whisper bypasses the queue; it is refused too, visibly.
chat=#A.H.chat
A.e.SlashCmdList.NEXUS('probe AutoPeer-Ebonhold')
check(table.concat(A.H.chat,'\n',chat+1):find('saved Sync mode is Off',1,true),'Off: the probe states the refusal')
P.Advance(5)
-- The actual submission boundary refuses too, independent of queue admission.
local W=A.e.Nexus.SyncWire
local okSend,whySend=W.SendPacket('WLRQ|OffPeer|x|y|c1-1-1|v',{queueClass='request',requester='OffPeer'},'1')
check(okSend==false and tostring(whySend):find('saved Sync mode is Off',1,true),'Off: SendPacket refuses at submission: '..tostring(whySend))
local okCan,whyCan=W.CanDispatch('WLRQ|OffPeer|x',{queueClass='request'})
check(okCan==false and tostring(whyCan):find('saved Sync mode is Off',1,true),'Off: CanDispatch refuses')
check(tostring(W.Blocked()):find('saved Sync mode is Off',1,true),'Off: the wire reports the saved mode as its blocker')
W.PumpHandshake()
check(Sent(A)==0,'Off: zero outbound calls on every route: '..Sent(A))
check(A.e.NexusDB.settings.syncMode=='off' and A.e.NexusDB.settingsVersion==5,'the saved mode and marker are unchanged')
check(A.e.Nexus.SyncWire.Stats().suspended==false,'a mode refusal never suspends the wire')
print('PASS sync_saved_mode_off: zero outbound (requests, responses, Share, handshakes, probe) with truthful refusals checks='..checks)
