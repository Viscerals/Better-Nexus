local H=dofile('tests/prototype/harness.lua');H.Boot()
local W,C=Nexus.SyncWire,Nexus.ChatThrottleLib
local checks=0;local function check(v,msg)assert(v,msg);checks=checks+1 end
local received={};W.Init(function(text,sender)received[#received+1]={text,sender};return true end)
local function refill() H.now=H.now+10;C.bQueueing=false;C.avail=4000;C.LastAvailUpdate=H.now end
refill();local before=#H.sent
check(W.CanDispatch('NEXUS|7|TEST',{})==true,'legacy room')
local ok,route=W.SendPacket('NEXUS|7|TEST',{},1)
check(ok and route=='legacy' and #H.sent==before+1,'one legacy send')
check(H.sent[#H.sent].route=='chat' and H.sent[#H.sent].text=='NEXUS||7||TEST','legacy bytes escaped once')
refill();W.ObservePeer('Remote-OtherRealm');W.PumpHandshake()
check(H.sent[#H.sent].route=='addon' and H.sent[#H.sent].text=='HELLO1','bounded handshake')
check(W.Receive(W.PREFIX,'ACK1','WHISPER','Remote-OtherRealm'),'ACK negotiated')
refill();before=#H.sent
ok,route=W.SendPacket('NEXUS|7|RESPONSE',{requester='Remote-OtherRealm'},1)
check(ok and route=='addon' and #H.sent==before+1,'exactly one negotiated directed send')
check(H.sent[#H.sent].target=='Remote-OtherRealm' and H.sent[#H.sent].text=='P7:NEXUS||7||RESPONSE','addon payload target')
check(W.Receive(W.PREFIX,'P7:NEXUS||7||RESPONSE','WHISPER','Remote-OtherRealm'),'negotiated receiver')
check(#received==1 and received[1][1]=='NEXUS||7||RESPONSE' and received[1][2]=='Remote-OtherRealm','same semantic receive owner')
check(not W.Receive(W.PREFIX,'P7:NEXUS||7||RESPONSE','WHISPER','Unknown'),'unknown peer payload refused')
check(not W.Receive(W.PREFIX,'ACK1','GUILD','Remote-OtherRealm'),'wrong distribution refused')
-- Long but legacy-legal packets retain one route without addon-envelope overflow.
refill();ok,route=W.SendPacket(string.rep('x',243),{requester='Remote-OtherRealm'},1)
check(ok and route=='legacy','oversized addon envelope uses one compatible route')
refill();H.combat=true;before=#H.sent
check(not W.CanDispatch('X',{requester='Remote-OtherRealm'}),'combat readiness blocked')
check(not W.SendPacket('X',{requester='Remote-OtherRealm'},1),'final combat guard')
W.ObservePeer('Second');W.PumpHandshake();check(#H.sent==before,'combat sends nothing')
H.combat=false;C.bQueueing=true
check(not W.SendPacket('X',{},1) and #H.sent==before,'occupied CTL retains Nexus packet outside CTL')
C.bQueueing=false;C.avail=0;C.LastAvailUpdate=H.now
check(not W.CanDispatch('X',{}),'byte budget respected')
refill();W.suspended=true
check(not W.SendPacket('X',{},1),'suspended backend cannot duplicate')
W.suspended=false
-- A real library queue for another producer uses the callback API and drains.
C.avail=0;C.LastAvailUpdate=H.now;local callbacks=0
C:SendChatMessage('NORMAL','Other','queued','WHISPER',nil,'Remote','Other.Fixed',function(_,sent)check(sent~=false,'queued callback success');callbacks=callbacks+1 end)
check(C.bQueueing==true,'external producer queue supported')
H.Advance(2,.1)
check(callbacks==1 and C.bQueueing==false,'queue drains and callback exactly once')
check(C.Prio.NORMAL.Ring.Add and C.Prio.NORMAL.Ring.Remove,'coexistent CTL ring shape')
-- Existing compatible/incompatible globals are never replaced.
ChatThrottleLib=C;local old=ChatThrottleLib;dofile('third_party/ChatThrottleLib.lua');check(ChatThrottleLib==old,'existing library retained')
ChatThrottleLib={version=100};dofile('third_party/ChatThrottleLib.lua');check(ChatThrottleLib.version==100 and Nexus.ChatThrottleLibUnavailable,'incompatible library isolated')
print('PASS CTL/negotiated wire/combat/coexistence checks='..checks)
