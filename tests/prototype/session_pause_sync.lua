-- Issue #171: the whole-addon session pause keeps Sync and sharing quiet.
-- Real TOC, Sync, Wire, Transport and the bundled ChatThrottleLib with its
-- immediate callback; the synthetic SendChatMessage / SendAddonMessage record
-- every native send. Each "nothing sent" has an unpaused control on this rig.
local function Boot()
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 local H=dofile('tests/prototype/harness.lua');H.Boot()
 function H.Sends(from)return #H.sent-(from or 0)end
 function H.Chat(from)return table.concat(H.chat,'\n',from or 1)end
 return H
end
local function UntilSent(H,seconds)
 local from=#H.sent
 for _=1,seconds*10 do H.Advance(.1,.05);if #H.sent>from then return true end end
 return false
end
local W=function()return Nexus.SyncWire end

-- S1. Control: a manual Sync is sent, a HELLO is answered and a direct packet
-- goes out. The diagnostic probe whisper is disabled in every mode (G-01,
-- core/SyncSession.lua SendStatusTo): unpaused, its compatibility facade is a
-- bare false and submits zero bytes; it is not a positive control.
do
 local H=Boot();H.sent={}
 SlashCmdList.NEXUS('sync')
 assert(UntilSent(H,40),'control: the manual Sync request is sent')
 local n=#H.sent
 assert(W().Receive(W().PREFIX,'HELLO1','WHISPER','Peer')==true,'control: a HELLO is admitted')
 H.Advance(3)
 assert(H.Sends(n)==1 and H.sent[#H.sent].text=='ACK1','control: the handshake reply is sent')
 n=#H.sent
 local ok=W().SendPacket('WLRQ|PrototypeTester|0,0,0,0',{},1)
 assert(ok and H.Sends(n)==1,'control: a direct packet is sent')
 n=#H.sent
 local probed,why=Nexus.Sync.SendStatusTo('Peer')
 assert(probed==false and why==nil,'control: the disabled diagnostic facade is an inert false with no reason: '..tostring(why))
 assert(H.Sends(n)==0,'control: the disabled diagnostic facade sends zero bytes, sends='..H.Sends(n))
end

-- S2. Paused: no manual request, no inbound admission or reply, no direct
-- packet, handshake or diagnostic whisper. The saved mode, the channel and
-- the transport fault flag are untouched. Resume itself sends nothing, and
-- after it the disabled diagnostic facade stays an inert false with no stale
-- pause reason and zero bytes (G-01: before/during/after the pause).
do
 local H=Boot()
 local mode=Nexus.SyncModePolicy.Mode()
 local channel=H.channel
 local n=#H.sent
 SlashCmdList.NEXUS('pause')
 local mark=#H.chat+1
 SlashCmdList.NEXUS('sync')
 assert(H.Chat(mark):find('paused',1,true),'the manual Sync is refused and says why: '..H.Chat(mark))
 assert(W().Receive(W().PREFIX,'HELLO1','WHISPER','Peer')==false,'no inbound admission')
 assert(not Nexus.Sync.HandleNativeChannelIncoming('WLRQ|Peer|0,0,0,0','Peer'),'no native channel admission')
 assert(not W().SendPacket('WLRQ|PrototypeTester|0,0,0,0',{},1),'no direct packet')
 local probeMark=#H.sent
 local probed,why=Nexus.Sync.SendStatusTo('Peer')
 assert(probed==false and why=='Nexus paused for this session','no diagnostic whisper; the pause reason keeps precedence: '..tostring(why))
 assert(H.Sends(probeMark)==0,'the paused diagnostic facade sends zero bytes')
 H.Advance(60)
 assert(H.Sends(n)==0,'nothing sent while paused, sends='..H.Sends(n))
 assert(Nexus.SyncModePolicy.Mode()==mode and H.channel==channel,'saved mode and channel unchanged')
 assert(W().Stats().suspended==false,'the transport fault flag is not used for the pause')
 SlashCmdList.NEXUS('resume')
 assert(H.Sends(n)==0,'Resume itself sends nothing')
 assert(not Nexus.SessionPause.IsPaused(),'fixture: the session is resumed')
 local after,afterWhy=Nexus.Sync.SendStatusTo('Peer')
 assert(after==false and afterWhy==nil,'after Resume: the disabled diagnostic facade is an inert false with no stale pause reason: '..tostring(afterWhy))
 assert(H.Sends(n)==0,'after Resume: the disabled diagnostic facade sends zero bytes, sends='..H.Sends(n))
end

-- S3. Work queued before the pause is not released by Resume. A manual Sync
-- held in combat waits in the queue; the pause ends it, and after Resume the
-- queue holds nothing from before the pause.
do
 local C=Boot();C.combat=true
 SlashCmdList.NEXUS('sync');C.Advance(5)
 C.combat=false
 assert(UntilSent(C,10),'control: unpaused, the request held in combat is sent once combat ends')
end
do
 local H=Boot();H.combat=true
 SlashCmdList.NEXUS('sync');H.Advance(5)
 local n=#H.sent
 assert(H.Sends(n)==0,'held in combat: queued, not sent')
 SlashCmdList.NEXUS('pause');H.combat=false
 H.Advance(30)
 assert(H.Sends(n)==0,'nothing sent while paused')
 SlashCmdList.NEXUS('resume')
 local queued=Nexus.Sync.Stats and Nexus.Sync.Stats().queue
 H.Advance(2)
 assert(H.Sends(n)==0,'the pre-pause request is not sent after Resume, sends='..H.Sends(n)..' queue='..tostring(queued))
end

-- S4. A Pause and Resume with no update between them: the packet queued
-- before the pause is still never sent.
do
 local H=Boot();H.combat=true
 SlashCmdList.NEXUS('sync');H.Advance(5)
 local n=#H.sent
 SlashCmdList.NEXUS('pause');SlashCmdList.NEXUS('resume');H.combat=false
 H.Advance(2)
 assert(H.Sends(n)==0,'the packet queued before a quick pause is not sent, sends='..H.Sends(n))
end

print('PASS session pause keeps Sync and sharing quiet')
