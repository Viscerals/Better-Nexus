-- Saved Sync mode Manual (accepted format 5): idle sends nothing; an explicit
-- Sync Now sends only its own requests and their follow-ups, for its existing
-- fixed lifetime; an explicit Share sends its summary and answers peers that
-- fetch that record; unrelated traffic stays unauthorized; expiry and a mode
-- change end permission through the existing handling. Two real runtimes.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local A,B=P.Boot({'ManualPeer','AutoPeer'},{5,8},function(i,db)
 if i~=1 then return end
 db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode='manual'
end)
local function FromA(since)
 local codes={}
 for i=since+1,#P.trace do local t=P.trace[i];if t.from==A.name then codes[#codes+1]=t.code end end
 return codes
end
local function Only(codes,allowed,label)
 for _,c in ipairs(codes)do check(allowed[c],label..': unexpected '..c..' from the Manual peer') end
end
local S=A.e.Nexus.Sync
check(A.e.Nexus.SyncModePolicy.Mode()=='manual','the accepted format-5 Manual choice is honored')
check(#A.H.sent==0,'Manual idle: nothing sent during start-up')

-- 1. Idle: no login Sync, no answer to the automatic peer, no handshake.
P.Advance(40);B.e.Nexus.Sync.RequestSync();P.Advance(20)
A.H.Fire('CHAT_MSG_ADDON','NEXUS_P1','HELLO1','WHISPER','AutoPeer-Ebonhold');P.Advance(5)
check(#A.H.sent==0,'Manual idle: nothing sent: '..#A.H.sent)
check((A.e.Nexus.Sync.Stats().modeRefused or 0)==0 and (A.e.Nexus.Sync.Stats().admittedPackets or 0)==0,
 'Manual idle: answers to the peer are not even scheduled, so nothing is refused or queued')

-- 2. Explicit Sync Now: only its own requests and follow-ups; unrelated
-- answers to the other peer's request stay unauthorized during it. The other
-- peer owns a record this peer has never seen (shared while it was away:
-- those packets are discarded, not delivered).
local peerId=P.Post(B,'NEXUS-TEST-PEER-OWNED')
for i=1,200 do B.H.Advance(.05,.05) end
B.cursor=#B.H.sent
check(A.e.Nexus.BuildCatalog.Get(peerId)==nil,'fixture: the Manual peer has not seen the record')
-- This side also owns a record the other peer lacks (its Share packets are
-- discarded, as if the other peer were away). Answering the other peer's
-- request during this side's Sync Now would carry it: that must not happen.
local hiddenId=P.Post(A,'NEXUS-TEST-MANUAL-HIDDEN')
for i=1,240 do A.H.Advance(.05,.05) end
A.cursor=#A.H.sent
local sentBeforeSync=#A.H.sent
local mark=#P.trace
A.e.SlashCmdList.NEXUS('sync')
check(A.e.Nexus.SyncModePolicy.ActiveManualGrant()~=nil,'Sync Now holds a manual grant')
P.Advance(3);B.e.Nexus.Sync.RequestSync()
P.Until(function()return P.Full(A,peerId)~=nil end,6000)
local codes=FromA(mark)
check(#codes>0,'Manual Sync Now sends')
Only(codes,{WLRQ=true,WLLQ=true},'Manual Sync Now')
check(B.e.Nexus.BuildCatalog.Get(hiddenId)==nil,'Manual Sync Now: unrelated answers stay unauthorized; the other peer did not get the record held by this side')
check(P.Full(A,peerId)~=nil,'Manual Sync Now completes: the missing record is received with its Echo list')
P.Until(function()return A.e.Nexus.SyncModePolicy.ActiveManualGrant()==nil end,12000)
check(A.e.Nexus.SyncModePolicy.ActiveManualGrant()==nil,'the grant ends with the operation')

-- 3. Back to idle: a new request from the other peer gets no answer.
mark=#P.trace;local sent=#A.H.sent
B.e.Nexus.Sync.RequestSync();P.Advance(30)
check(#A.H.sent==sent,'Manual idle after the operation: nothing sent')
-- Let the other peer's own unanswered request reach its fixed lifetime: its
-- existing hold on arriving records then ends (peer behavior, not this mode).
P.Advance(300)
check(#A.H.sent==sent,'Manual idle: still nothing sent while the peer keeps asking')

-- 4. Explicit Share: its summary, and answers to the peer fetching that record.
mark=#P.trace
local id=P.Post(A,'NEXUS-TEST-MANUAL-SHARE')
P.Until(function()return P.Full(B,id)~=nil end,6000)
codes=FromA(mark)
Only(codes,{WLBI=true,WLLC=true,WLRB=true},'Manual Share')
local hasSummary=false;for _,c in ipairs(codes)do if c=='WLBI' then hasSummary=true end end
check(hasSummary,'the Share summary is sent without a separate Sync Now')
check(P.Full(B,id)~=nil,'the peer stores the shared record with its Echo list')
local channel=A.e.Nexus.Sync.ChannelName()
local function Fetch(buildId)
 A.H.Fire('CHAT_MSG_CHANNEL','WLLQ|AutoPeer|'..buildId,'AutoPeer-Ebonhold',nil,'1. '..channel,nil,nil,nil,nil,channel)
end
local function SentAbout(buildId,since)
 for k=since+1,#A.H.sent do if A.H.sent[k].text:find(buildId,1,true) then return true end end
 return false
end
-- During the Share window a fetch for a different build is not answered.
local since=#A.H.sent;Fetch(hiddenId);P.Advance(20)
check(not SentAbout(hiddenId,since),'Manual: a fetch for another build during a Share window is not answered')
-- After the Share's own 120-second expiry a fetch for the shared build is not answered.
P.Advance(130);since=#A.H.sent;Fetch(id);P.Advance(20)
check(not SentAbout(id,since),'Manual: after the Share expiry a fetch for that build is not answered')
local kind=A.e.Nexus.CommunityBuilds.ShareStatusText(id)
check(kind=='sent','the Share status is truthful (sent, peer receipt not claimed): '..tostring(kind))
check(A.e.NexusDB.settings.syncMode=='manual' and A.e.NexusDB.settingsVersion==5,'the saved mode and marker are unchanged')
-- No handshake is answered under Manual, so no addon whisper may depend on one:
-- every packet from this side used the legacy route the peer accepts.
for _,packet in ipairs(A.H.sent)do
 check(packet.route=='chat' and packet.kind=='CHANNEL','Manual: legacy route only, never an unconfirmed addon whisper: '..tostring(packet.route))
end

-- 5. Expiry: a Sync Now request held by combat past the operation's fixed
-- lifetime is never released afterwards.
local function Ended()local st=A.e.Nexus.Sync.Stats();return (st.modeDropped or 0)+(st.expiredRemoved or 0)+(st.supersededRemoved or 0)end
A.H.combat=true;sent=#A.H.sent;local endedBefore=Ended()
local ok=S.RequestSync();check(ok==true or ok==nil,'Sync Now accepted before combat ends')
P.Advance(310)
check(A.e.Nexus.SyncModePolicy.ActiveManualGrant()==nil,'the grant ends at the existing lifetime; pending work does not extend it')
A.H.combat=false;P.Advance(10)
check(#A.H.sent==sent,'the expired request is dropped, not released: '..(#A.H.sent-sent))
check(Ended()>endedBefore,'the expired request ended through existing terminal handling (expired, superseded or mode), not held at the queue head')
local dropped=A.e.Nexus.Sync.Stats().modeDropped or 0

-- 6. Mode changes (as an existing control would store them).
-- Manual -> Off while a Sync Now request is queued: the operation ends through
-- the existing cancellation and its queued request is never submitted.
sent=#A.H.sent;local endedBefore2=Ended()
local ok2=S.RequestSync();check(ok2==true,'a new manual Sync Now is accepted')
A.e.NexusDB.settings.syncMode='off'
P.Advance(20)
check(#A.H.sent==sent,'Manual -> Off: the queued request is not submitted: '..(#A.H.sent-sent))
check(A.e.Nexus.SyncModePolicy.ActiveManualGrant()==nil,'Manual -> Off: the grant is gone')
check(Ended()>endedBefore2,'Manual -> Off: the queued request ended through the existing cancellation, not held')
check(A.e.Nexus.Sync.Stats().terminalReason=='sync_mode','Manual -> Off: the operation ends with a truthful sync-mode terminal reason: '..tostring(A.e.Nexus.Sync.Stats().terminalReason))
-- Off -> automatic: answers to the other peer resume; -> Off again: they stop.
A.e.NexusDB.settings.syncMode='automatic';sent=#A.H.sent
local droppedBefore=A.e.Nexus.Sync.Stats().modeDropped or 0
-- The first chunk of a multi-chunk answer switches the saved mode to Off while
-- the remaining chunk is already queued (this side's record the peer lacks).
local switched=false
P.before=function(p,q,code)
 if not switched and p==A and code=='WLRB' then
  local index,total=p.H.sent[p.cursor].text:gsub('||','|'):match('|(%d+)/(%d+)|')
  if index and total and tonumber(index)<tonumber(total) then switched=true;A.e.NexusDB.settings.syncMode='off' end
 end
end
B.e.Nexus.Sync.RequestSync()
P.Until(function()return switched end,4000)
P.before=nil
check(switched,'automatic: the peer is answered again')
P.Advance(20)
check((A.e.Nexus.Sync.Stats().modeDropped or 0)>droppedBefore,'automatic -> Off: queued answers are dropped at the pump with the mode reason, not held or released')
sent=#A.H.sent
P.Advance(20);B.e.Nexus.Sync.RequestSync();P.Advance(30)
check(#A.H.sent==sent,'Off after a change: nothing more is sent: '..(#A.H.sent-sent))
check(A.e.Nexus.SyncWire.Stats().suspended==false,'mode refusals never suspend the wire')
print('PASS sync_saved_mode_manual: idle silent; Sync Now and Share send only their own traffic; unrelated traffic unauthorized; expiry and mode changes end permission checks='..checks)
