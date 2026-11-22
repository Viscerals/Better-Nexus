-- Issue #171 review repairs (Spec F2-F5). While Nexus is paused, a timely
-- acknowledgment still settles a handshake sent before the pause (once, for
-- that peer, inside its window). Work prepared before a pause - a manual Sync
-- still waiting for its hashes, a queued handshake - is not sent after Resume,
-- even when Pause and Resume fall between two updates. A start-up that
-- completes while paused joins no channel and starts no Sync until Resume.
-- Real TOC, Sync, Wire and bundled ChatThrottleLib; every native send counted.
local failures={}
local function Case(name,fn)
 local ok,err=pcall(fn)
 print((ok and 'CASE PASS ' or 'CASE FAIL ')..name..(ok and '' or (': '..tostring(err))))
 if not ok then failures[#failures+1]=name end
end
local function Load(before)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusPanel=nil
 local H=dofile('tests/prototype/harness.lua')
 if before then before(H) end
 return H
end
local function Boot(before) local H=Load(before);H.Boot();return H end
local function W() return Nexus.SyncWire end
local function Texts(H,from,kind)
 local n=0
 for i=(from or 0)+1,#H.sent do if H.sent[i].text==kind then n=n+1 end end
 return n
end
-- A HELLO sent to Peer by the wire's own handshake pump.
local function Hello(H)
 W().ObservePeer('Peer');H.Advance(2)
 assert(Texts(H,0,'HELLO1')==1,'setup: one HELLO1 sent to Peer')
end
-- Whether a directed packet to Peer now uses the negotiated addon route.
local function Negotiated(H)
 local n=#H.sent
 assert(W().SendPacket('WLRQ|PrototypeTester|0,0,0,0',{requester='Peer'},1),'directed packet sent')
 return #H.sent==n+1 and H.sent[#H.sent].route=='addon'
end

-- C1. ACK settlement of a HELLO sent before the pause.
Case('C1 control',function()
 local H=Boot();Hello(H)
 assert(W().Receive(W().PREFIX,'ACK1','WHISPER','Peer')==true,'unpaused ACK settles')
 assert(Negotiated(H),'unpaused: the peer is negotiated')
end)
Case('C1 timely ACK while paused',function()
 local H=Boot();Hello(H)
 SlashCmdList.NEXUS('pause')
 local n=#H.sent
 assert(W().Receive(W().PREFIX,'ACK1','WHISPER','Other')==false,'an ACK from another peer is refused')
 assert(W().Receive(W().PREFIX,'ACK1','WHISPER','Peer')==true,'the timely ACK settles the HELLO sent before the pause')
 assert(W().Receive(W().PREFIX,'ACK1','WHISPER','Peer')==false,'a duplicate ACK is refused: the window is used once')
 assert(W().Receive(W().PREFIX,'HELLO1','WHISPER','Other')==false,'a new HELLO is still refused while paused')
 H.Advance(3)
 assert(#H.sent==n,'settlement sends nothing')
 SlashCmdList.NEXUS('resume')
 assert(Negotiated(H),'after Resume the settled peer is negotiated')
end)
Case('C1 expired ACK while paused',function()
 local H=Boot();Hello(H)
 SlashCmdList.NEXUS('pause');H.Advance(40)
 assert(W().Receive(W().PREFIX,'ACK1','WHISPER','Peer')==false,'an ACK after the window is refused')
 SlashCmdList.NEXUS('resume')
 assert(not Negotiated(H),'the peer is not negotiated by a late ACK')
end)

-- C2. A manual Sync still preparing (its hashes not ready) is not sent after
-- a Pause and Resume between two updates.
local function Preparing(H)
 local D=Nexus.DpsCapture;local hash=D.GetSyncHash
 D.GetSyncHash=function() return nil end
 local ok,why=Nexus.Sync.RequestSync()
 assert(ok==nil and Nexus.Sync.Stats().preparingRequest,'setup: the manual request is preparing: '..tostring(why))
 return function() D.GetSyncHash=hash end
end
Case('C2 control',function()
 local H=Boot();local restore=Preparing(H);local n=#H.sent
 restore();H.Advance(5)
 assert(#H.sent>n,'unpaused: the prepared manual request is sent once its hashes are ready')
end)
Case('C2 quick pause',function()
 local H=Boot();local restore=Preparing(H);local n=#H.sent
 SlashCmdList.NEXUS('pause');SlashCmdList.NEXUS('resume')
 restore();H.Advance(5)
 assert(#H.sent==n,'the pre-pause preparing request is not sent after Resume, sends='..(#H.sent-n))
 assert(not Nexus.Sync.Stats().preparingRequest,'it ended')
end)

-- C3. A handshake reply queued before the pause is not sent after Resume.
Case('C3 control',function()
 local H=Boot();H.combat=true
 assert(W().Receive(W().PREFIX,'HELLO1','WHISPER','Peer')==true,'HELLO admitted')
 H.Advance(2);local n=Texts(H,0,'ACK1');assert(n==0,'held in combat')
 H.combat=false;H.Advance(3)
 assert(Texts(H,0,'ACK1')==1,'unpaused: the queued ACK is sent after combat')
end)
Case('C3 quick pause',function()
 local H=Boot();H.combat=true
 assert(W().Receive(W().PREFIX,'HELLO1','WHISPER','Peer')==true,'HELLO admitted')
 H.Advance(2)
 SlashCmdList.NEXUS('pause');SlashCmdList.NEXUS('resume')
 H.combat=false;H.Advance(3)
 assert(Texts(H,0,'ACK1')==0,'the pre-pause queued ACK is not sent after Resume')
end)

-- C4. Start-up completing while paused: no channel join, no Sync request.
local function Joins(H)
 H.joins=0
 GetChannelList=function() if H.joined then return 1,'wrbuildssync' end end
 GetChannelName=function() if H.joined then return 1,'wrbuildssync' end return 0 end
 JoinTemporaryChannel=function() H.joins=H.joins+1;H.joined=true end
 JoinChannelByName=JoinTemporaryChannel
end
local function Start(H,pause)
 for line in io.lines('Nexus.toc') do
  line=line:gsub('\r','')
  if line~='' and not line:match('^#') then
   local chunk,err=loadfile((line:gsub('\\','/')));assert(chunk,err);chunk('Nexus',{})
  end
 end
 if pause then SlashCmdList.NEXUS('pause') end
 H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD');H.Advance(30,.05)
end
Case('C4 control',function()
 local H=Load(Joins);Start(H,false)
 assert(H.joins>=1,'unpaused: start-up joins the Sync channel')
end)
Case('C4 paused start-up',function()
 local H=Load(Joins);Start(H,true)
 assert(Nexus.StartupStatus().state=='ready','start-up integrity still completes while paused')
 assert(H.joins==0 and #H.sent==0,'no channel join and no send while paused: joins='..H.joins..' sends='..#H.sent)
 SlashCmdList.NEXUS('resume')
 assert(H.joins==0,'Resume itself joins nothing')
 H.Advance(3)
 assert(H.joins>=1,'a later unpaused turn admits the shared start-up')
end)

assert(#failures==0,'failed cases: '..table.concat(failures,', '))
print('PASS session pause settles sent handshakes and drops stale Sync work')
