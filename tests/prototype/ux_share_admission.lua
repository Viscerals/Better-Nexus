-- M5R2-MB1 (continuation 42): a confirmed Share of your own Saved Build is
-- the explicit Share operation it is, end to end, in two real runtimes
-- (sync_pair_support; only packets captured from real SendChatMessage calls
-- cross the bridge). The route is the production one: the Build Library's
-- Share Build... action and its confirmation (the harness StaticPopup model,
-- H.AcceptPopup) -> controller PublishImportedBuild (one catalog maintenance
-- commit of the listing and the mirror's publication) -> Sync
-- BroadcastBuildSummary -> Transport admission and final submit -> the
-- captured packets, delivered to the other runtime, whose own fetch is
-- answered or refused by the saved mode.
-- Healthy behaviour (EXPECT, fails on the closed aeb35417 source by design:
-- there the Share is handed to Sync with no options, as an untracked bulk
-- summary, so Manual refuses it at admission, and its result is discarded
-- while the line says "Sync was asked to send it"):
--  S1  Automatic admits it as the explicit Share operation, and the line
--      says it was queued, not sent or received.
--  S2  explicit-choice Manual admits it after the local commit, with its own
--      120-second deadline; exactly one summary leaves, decoded with the
--      actual codec: the listing's identity and Echo count, no Echo list or
--      description; the other peer's fetch is answered for that requester
--      before the deadline and the peer stores the Echo list.
--  S3  an oversize summary is a final, visible refusal after the local save,
--      also in Sync's own Share record.
--  S4  admitted under Manual, then Off before submission: the final-submit
--      check drops it with the saved-mode reason before its deadline.
--  S5  Off: Sync's own Share record is the final refusal with the Off reason.
--  S6  Sync unavailable: the line states it after the local save.
--  L1  accepted legacy Manual (format 5, no explicit choice): as S2,
--      including the expiry.
-- Unchanged (GUARD, holds on aeb too): Automatic sends exactly one summary
-- and the peer stores the record; idle, viewing and a cancelled confirmation
-- send nothing; one approval starts one Share; no Echo list precedes a peer's
-- fetch; a fetch for another listing, or after the deadline, is not answered;
-- only the Share's own codes leave under Manual; Off sends nothing and says
-- so; the oversize and unavailable listings are saved locally and nothing of
-- them is queued; the DPS-best hand-off is one call with the listing ID only;
-- the stored Sync mode bytes; no game action.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- Fault model, disclosed: S4 holds the wire with the harness combat flag
-- (InCombatLockdown), as sync_saved_mode_manual does; S6 removes the two
-- Sync summary entries for the one confirmed Share and restores them.
-- Limits: the bridge models no loss, throttling or latency; an undecodable
-- summary is not produced by this sender and is only counted (zero); the
-- popup is the harness model, not native StaticPopup layout. Not native
-- evidence.
local Pair=dofile('tests/prototype/sync_pair_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('ux_share_admission')
local unpackAll=table.unpack or unpack

local DIALOG='NEXUS_SHARE_SAVED_BUILD'
-- core/Sync.lua: CHAT_LIMIT 255 - CHAT_SAFETY 8 escaped bytes per summary
-- line; SHARE_RETRY_MAX_AGE 120 seconds, the explicit Share's deadline.
local BUDGET,SHARE_AGE=247,120
-- Summary fields core/SyncCompatibility.lua SummaryEncode may carry.
local SUMMARY_KEYS={id=true,t=true,a=true,o=true,c=true,m=true,h=true,lh=true,n=true,x=true}
local LONG='Oversize Share Title Long Enough That Its Summary Cannot Fit One Line'
local TITLES={[1]='Admission Auto',[2]='Admission Manual',[3]=LONG,
 [4]='Admission Mode Change',[5]='Admission Off',[6]='Admission No Sync'}
local function E(id,stacks) return {spellId=id,quality=(id-200000)%4,stacks=stacks} end
local function Slots(titles)
 local slots={}
 for slot,title in pairs(titles) do
  slots[slot]={name=title,verified=true,echoes={E(200000+slot*4-3,2),E(200000+slot*4-2,1)}}
 end
 return slots
end

-- Every step of both runtimes stamps the packets each observed peer sent in
-- it (sends happen only while time passes).
local live={}
local function Stamp(P)
 local sent=P.peer.H.sent
 for i=(P.stamped or 0)+1,#sent do P.stamps[i]=P.peer.H.now end
 P.stamped=#sent
end
local function Step() Pair.Step();for _,P in ipairs(live) do Stamp(P) end end
local function Advance(seconds) for _=1,math.floor(seconds/.05+.5) do Step() end end
-- Checked before each step; nil when the limit passes first.
local function Until(predicate,limit)
 for i=0,limit do
  if predicate() then return i end
  if i<limit then Step() end
 end
 return nil
end

-- The peer's own Sync session and transport queue, as ux_sync_mode_transitions
-- reads them (upvalues of Sync's update steps).
local function Upvalue(fn,name)
 if type(fn)~='function' then return nil end
 for i=1,255 do
  local n,v=debug.getupvalue(fn,i)
  if not n then break end
  if n==name then return v end
 end
end
local META={'queueClass','operationKind','operationKey','buildId','requester','requestId',
 'transferId','enqueuedAt','expiresAt','manualGrant'}
local function Scalars(t)
 local out={}
 if type(t)=='table' then
  for _,k in ipairs(META) do
   local v=t[k];local kind=type(v)
   if kind=='string' or kind=='number' or kind=='boolean' then out[k]=v end
  end
 end
 return out
end
local function Pack(...) return {n=select('#',...),...} end

-- One observed peer: its print lines, packet times, transport admissions,
-- transport events and DPS-best hand-offs. Every recorder passes the call
-- through with its own arguments and returns the real results.
local function Open(peer)
 local P={peer=peer,name=(peer.e.UnitName()),said={},stamps={},admissions={},events={},dps={},seq=0}
 local realPrint=peer.e.print
 peer.e.print=function(...)
  local t={}
  for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end
  P.said[#P.said+1]=table.concat(t,' ')
  return realPrint(...)
 end
 P.stamped=#peer.H.sent
 return P
end
local function Record(P)
 local session,transport
 local steps=P.peer.e.Nexus.Sync._defaultSteps
 for _,step in ipairs(type(steps)=='table' and steps or {}) do
  if step.name=='auto.sync' then session=Upvalue(step.run,'Session') end
  if step.name=='transport.pump' then transport=Upvalue(step.run,'Transport') end
 end
 local function Next() P.seq=P.seq+1;return P.seq end
 if type(transport)=='table' then
  for _,name in ipairs({'Enqueue','EnqueueBatch','EnqueueControl'}) do
   local real=transport[name]
   if type(real)=='function' then
    transport[name]=function(payload,metadata,...)
     local n,at=Next(),P.peer.H.now
     local r=Pack(real(payload,metadata,...))
     P.admissions[#P.admissions+1]={n=n,at=at,route=name,queued=r[1],why=r[2],
      chunks=type(payload)=='table' and #payload or 1,
      text=type(payload)=='string' and payload or type(payload)=='table' and payload[1] or nil,
      m=Scalars(metadata)}
     return unpackAll(r,1,r.n)
    end
   end
  end
 end
 if type(session)=='table' and type(session.HandleTransportEvent)=='function' then
  local real=session.HandleTransportEvent
  session.HandleTransportEvent=function(kind,fields,metadata,...)
   P.events[#P.events+1]={n=Next(),at=P.peer.H.now,kind=kind,
    reason=type(fields)=='table' and fields.reason or nil,m=Scalars(metadata)}
   return real(kind,fields,metadata,...)
  end
 end
 local D=P.peer.e.Nexus.DpsCapture
 local best=D and D.BroadcastBestForBuild
 if type(best)=='function' then
  D.BroadcastBestForBuild=function(...)
   P.dps[#P.dps+1]={count=select('#',...),id=(select(1,...))}
   return best(...)
  end
 end
 return type(transport)=='table' and type(session)=='table' and type(best)=='function'
end
local function AdmissionText(a)
 if not a then return 'none' end
 return a.route..' queued='..printable(a.queued)..' why='..printable(a.why)..' class='..printable(a.m.queueClass)
  ..' kind='..printable(a.m.operationKind)..' chunks='..printable(a.chunks)
  ..' enqueuedAt='..printable(a.m.enqueuedAt)..' expiresAt='..printable(a.m.expiresAt)
end
local function StatusText(s)
 if not s then return 'none' end
 return 'outcome='..printable(s.outcome)..' reason='..printable(s.reason)..' terminal='..printable(s.terminal)
  ..' queueAdmitted='..printable(s.queueAdmitted)..' sendCompleted='..printable(s.sendCompleted)
end
local function SaidSince(P,mark,needle)
 for i=mark+1,#P.said do
  local line=V.Plain(P.said[i])
  if line:find(needle,1,true) then return line end
 end
 return nil
end

-- Wire fields after the chat escape and the addon protocol tag are removed
-- (core/Sync.lua formats); the escaped length counts each "|" twice
-- (core/SyncProtocol.lua EscapedLen).
local function Fields(text)
 local plain=tostring(text or ''):gsub('||','|'):gsub('^P%d+:','')
 local f={}
 for field in (plain..'|'):gmatch('([^|]*)|') do f[#f+1]=field end
 return f,plain
end
local function Escaped(plain) return #plain+select(2,plain:gsub('|','')) end
local function Decode(P,data)
 local codec=P.peer.e.Nexus.Codec
 local ok,raw=pcall(codec.Base64Decode,data)
 if not ok or type(raw)~='string' then return nil end
 local ok2,t=pcall(codec.JSONDecode,raw)
 return ok2 and type(t)=='table' and t or nil
end
-- The Share summaries of `id` this peer sent since `since` (WLBI with no
-- response context), decoded with the actual codec; undecodable summaries
-- and contextual response summaries of it are counted apart.
local function Summaries(P,id,since)
 local out,bad,contextual={},0,0
 for i=(since or 0)+1,#P.peer.H.sent do
  local f,plain=Fields(P.peer.H.sent[i].text)
  if f[1]=='WLBI' then
   local data=Decode(P,f[3])
   if not data then bad=bad+1
   elseif data.id==id and #f==3 then
    out[#out+1]={index=i,data=data,plain=plain,bytes=Escaped(plain),at=P.stamps[i]}
   elseif data.id==id then contextual=contextual+1 end
  end
 end
 return out,bad,contextual
end
local function Stacks(row)
 local n=0
 for _,e in ipairs(type(row)=='table' and type(row.echoes)=='table' and row.echoes or {}) do
  n=n+(tonumber(e.stacks or e.count) or 1)
 end
 return n
end
-- The listing's summary as SummaryEncode and PrepareSummary build it, for its
-- escaped size (S1 checks this against the actual wire).
local function SummaryBytes(P,row)
 if type(row)~='table' or row.link~=nil then return nil end
 local codec=P.peer.e.Nexus.Codec
 local payload={id=row.id,t=row.title,a=row.author,o=row.ownerKey,c=row.class,
  m=tonumber(row.lastModified) or tonumber(row.postedAt) or 0,h=row.fingerprintHash,
  n=Stacks(row),x=row.autoDps and 1 or nil}
 local _,plain=Fields('WLBI|'..P.name..'|'..codec.Base64Encode(codec.JSONEncode(payload)))
 return Escaped(plain)
end
local function IdentityOf(data,row)
 return type(data)=='table' and type(row)=='table' and data.id==row.id and data.t==row.title
  and data.a==row.author and data.o==row.ownerKey and data.c==row.class
  and data.m==tonumber(row.lastModified) and data.h==row.fingerprintHash
  and data.n==Stacks(row) and data.lh==nil
end
local function EchoFree(data)
 if type(data)~='table' or type(data.n)~='number' then return false end
 for k in pairs(data) do if not SUMMARY_KEYS[k] then return false end end
 return true
end
local function SummaryText(sums,bad,contextual)
 local s=sums[1]
 return #sums..' summary(ies), '..bad..' undecodable, '..(contextual or 0)..' contextual'
  ..(s and (' first: '..s.bytes..' escaped bytes, keys='..(function()
   local keys={};for k in pairs(s.data) do keys[#keys+1]=k end;table.sort(keys);return table.concat(keys,',')
  end)()) or '')
end
local function SentAbout(P,id,since)
 for k=since+1,#P.peer.H.sent do if P.peer.H.sent[k].text:find(id,1,true) then return true end end
 return false
end
local function FirstSent(P,since,match)
 for k=since+1,#P.peer.H.sent do
  if match((Fields(P.peer.H.sent[k].text))) then return P.stamps[k] end
 end
 return nil
end
local function Codes(P,since)
 local codes={}
 for k=since+1,#P.peer.H.sent do codes[#codes+1]=(Fields(P.peer.H.sent[k].text))[1] end
 return codes
end
local function QueuedSince(P,seq,id)
 for _,a in ipairs(P.admissions) do
  if a.n>seq and a.queued==true and (id==nil or a.m.buildId==id) then return a end
 end
 return nil
end
-- A peer fetching one listing (WLLQ), fired at this runtime as the bridge
-- would deliver it (as sync_saved_mode_manual Fetch).
local function Fetch(P,id,short)
 local channel=P.peer.e.Nexus.Sync.ChannelName()
 P.peer.H.Fire('CHAT_MSG_CHANNEL','WLLQ|'..short..'|'..id,short..'-Ebonhold',nil,'1. '..channel,nil,nil,nil,nil,channel)
end
-- The saved Sync mode bytes: the explicit choice key, the old syncMode and
-- the format marker.
local function ModeBytes(P)
 local db=P.peer.e.NexusDB
 local settings=rawget(db,'settings') or {}
 local key=(P.peer.e.Nexus.SyncModePolicy.Choice() or {}).key or 'nexusSyncModeChoice'
 return printable(rawget(settings,key))..'|'..printable(rawget(settings,'syncMode'))..'|'..printable(rawget(db,'settingsVersion'))
end
local function DpsHandoffs(P,mark,id)
 local exact,other=0,0
 for i=mark+1,#P.dps do
  if P.dps[i].id==id and P.dps[i].count==1 then exact=exact+1 else other=other+1 end
 end
 return exact,other
end

-- The Build Library of one peer.
local function CB(P) return P.peer.e.Nexus.CommunityBuilds end
local function Ready(P)
 local stats=CB(P).VirtualStats()
 local import=type(stats)=='table' and type(stats.savedImport)=='table' and stats.savedImport or {}
 local status=P.peer.e.Nexus.BuildCatalog.ManualPreparationStatus()
 return import.pending~=true and type(status)=='table' and status.ready==true
end
local function Mirror(P,slot)
 local found
 for _,b in pairs(CB(P).Builds() or {}) do
  if type(b)=='table' and b.importedSavedBuild==true and tonumber(b.serverSlot)==slot then found=b end
 end
 return found
end
local function Panel(P) local f=P.peer.e.NexusCommunityBuildsFrame;return f and f._detailPanel end
local function ShowBuild(P,id)
 CB(P).ShowBuild(id)
 Until(function() local p=Panel(P);return p and p:IsShown() and p._nexusShownId==id and Ready(P) end,2000)
 local p=Panel(P)
 return p and p:IsShown() and p._nexusShownId==id and p or nil
end
-- Opens the confirmation through the mirror's own action.
local function Confirm(P,mirrorId,tag)
 local panel=ShowBuild(P,mirrorId)
 local share=panel and panel.shareBtn
 C.setup(share~=nil and share:IsShown() and share:IsEnabled(),tag..': fixture: the mirror is shown with its Share Build... action')
 if not (share and share:IsShown() and share:IsEnabled()) then return nil end
 P.peer.H.popup=nil
 share:Click()
 local popup=P.peer.H.popup
 local bound=popup~=nil and popup.which==DIALOG and type(popup.data)=='table' and popup.data.id==mirrorId
 C.setup(bound,tag..': fixture: the action opened the Share confirmation bound to this mirror',printable(popup and popup.which))
 return bound and popup or nil
end
local function Completion(P,mark)
 return SaidSince(P,mark,'locally as your shared listing') or SaidSince(P,mark,'Not shared:')
  or SaidSince(P,mark,'Share cancelled')
end
-- One confirmed Share through the real action and confirmation: Accept, then
-- the local commit settles at once or by its ticket.
local function Share(P,mirrorId,title,tag,beforeAccept)
 local popup=Confirm(P,mirrorId,tag)
 if not popup then return nil end
 local r={tag=tag,mirrorId=mirrorId,title=title,popup=popup,note=V.Plain(tostring(popup.arg2 or '')),
  sent=#P.peer.H.sent,mark=#P.said,seq=P.seq,trace=#Pair.trace,dps=#P.dps}
 if beforeAccept then beforeAccept(r) end
 r.at=P.peer.H.now
 P.peer.H.AcceptPopup()
 Until(function() return Completion(P,r.mark)~=nil end,400)
 r.line=Completion(P,r.mark)
 local catalog=P.peer.e.Nexus.BuildCatalog
 local mirror=catalog.Get(mirrorId)
 r.id=type(mirror)=='table' and mirror.publishedBuildId or nil
 r.listing=r.id and catalog.Get(r.id) or nil
 for _,a in ipairs(P.admissions) do
  if not r.admission and a.n>r.seq and r.id and a.m.buildId==r.id and type(a.text)=='string' and a.text:sub(1,5)=='WLBI|' then
   r.admission=a
  end
 end
 print('OBSERVED',tag,'listing='..printable(r.id),'line='..printable(r.line))
 print('OBSERVED',tag,'admission',AdmissionText(r.admission))
 C.setup(r.id~=nil,tag..': fixture: the confirmed Share settled with a published listing',printable(r.line))
 return r.id and r or nil
end
local function LocallySaved(r)
 return type(r.listing)=='table' and r.listing.sourceSavedBuildId==r.mirrorId and r.listing.title==r.title
end

-- The follow-up and expiry checks of one admitted Manual Share (S2, L1).
local function Followups(P,peerB,r,tag)
 local adm=r.admission
 local deadline=adm and adm.queued==true and adm.m.queueClass=='share' and tonumber(adm.m.expiresAt) or nil
 local limit=deadline and math.floor((deadline-2-P.peer.H.now)/.05) or 1200
 Until(function() return Pair.Full(peerB,r.id)~=nil end,math.max(0,limit))
 local sums,bad,contextual=Summaries(P,r.id,r.sent)
 local s=sums[1]
 print('OBSERVED',tag,'summaries',SummaryText(sums,bad,contextual))
 if s then
  print('OBSERVED',tag,'decoded summary','id='..printable(s.data.id),'t='..printable(s.data.t),'a='..printable(s.data.a),
   'o='..printable(s.data.o),'c='..printable(s.data.c),'m='..printable(s.data.m),'h='..printable(s.data.h),
   'n='..printable(s.data.n),'sent at='..printable(s.at),'deadline='..printable(deadline))
 end
 C.expect(#sums==1 and bad==0 and IdentityOf(s.data,r.listing) and EchoFree(s.data),
  tag..': exactly one summary of the listing leaves this client, decoded with the actual codec: the listing\'s identity, Echo count and hash, and no Echo list or description',
  SummaryText(sums,bad,contextual))
 C.expect(#sums==1 and adm~=nil and s.plain==adm.text and s.bytes<=BUDGET and deadline~=nil and s.at~=nil and s.at<deadline,
  tag..': it is the admitted entry, within the line budget, sent before its own deadline',
  printable(s and s.bytes)..' bytes at '..printable(s and s.at)..' / '..printable(deadline))
 -- The peer's fetch, answered for that requester under this Share.
 local answer
 for _,a in ipairs(P.admissions) do
  if a.n>r.seq and a.queued==true and a.route=='EnqueueBatch' and a.m.buildId==r.id
   and type(a.m.requester)=='string' and a.m.requester~='' and deadline and a.at<deadline then answer=answer or a end
 end
 local answeredAt=FirstSent(P,r.sent,function(f) return f[1]=='WLRB' and f[3]==r.id end)
 print('OBSERVED',tag,'follow-up','admitted for='..printable(answer and answer.m.requester)..' at='..printable(answer and answer.at),
  'first full-record chunk sent at='..printable(answeredAt),'peer stores Echo list='..printable(Pair.Full(peerB,r.id)~=nil))
 C.expect(answer~=nil and answeredAt~=nil and answeredAt<deadline and Pair.Full(peerB,r.id)~=nil,
  tag..': the other peer\'s fetch is answered under this Share before its deadline: the full record is admitted for that requester and sent, and the peer stores the Echo list',
  printable(answeredAt)..' / '..printable(deadline))
 -- No Echo list before a peer asked for it.
 local asked,early=nil,0
 for i=r.trace+1,#Pair.trace do
  local t=Pair.trace[i]
  if not asked and t.from==peerB.name and t.code=='WLLQ' and t.text:find(r.id,1,true) then asked=i end
 end
 for i=r.trace+1,#Pair.trace do
  local t=Pair.trace[i]
  if t.from==P.peer.name and (t.code=='WLRB' or t.code=='WLLC') and t.text:find(r.id,1,true) and (not asked or i<asked) then early=early+1 end
 end
 C.guard(early==0,tag..': no Echo list of the listing leaves this client before a peer asks for it',early)
 return deadline
end
local function Expiry(P,r,deadline,tag)
 local due=deadline or (r.at+SHARE_AGE)
 Until(function() return P.peer.H.now>=due+1 end,math.max(0,math.floor((due+1-P.peer.H.now)/.05)+2))
 local since=#P.peer.H.sent
 local unanswered=P.peer.e.Nexus.Sync.Stats().modeUnanswered or 0
 Fetch(P,r.id,'OtherPeer')
 Advance(20)
 print('OBSERVED',tag,'after the deadline','now='..printable(P.peer.H.now),'deadline='..printable(due),
  'modeUnanswered +'..((P.peer.e.Nexus.Sync.Stats().modeUnanswered or 0)-unanswered))
 C.guard(not SentAbout(P,r.id,since),tag..': after the Share\'s own deadline a fetch for the listing is not answered')
end

-- Peer A shares; peer B (Automatic) receives and fetches.
local A,B=Pair.Boot({'SharePeer','OtherPeer'},{5,8},nil,{slots={[1]=Slots(TITLES)}})
local PA=Open(A);live={PA}
local M={}
local r1
C.scenario('S0 fixture: two runtimes, six own Saved Builds imported through the Build Library',function()
 C.setup(A.e.Nexus.SyncModePolicy.Mode()=='automatic' and (A.e.Nexus.SyncModePolicy.Choice() or {}).explicit==nil,
  'S0: fixture: the sharing peer starts Automatic, with no explicit choice')
 C.setup(Record(PA),'S0: fixture: its transport admissions, transport events and DPS-best hand-offs are observed by pass-through recorders')
 CB(PA).Show()
 C.setup(Until(function()
  for slot=1,6 do if not Mirror(PA,slot) then return false end end
  return Ready(PA)
 end,4000)~=nil,'S0: fixture: all six server Saved Builds are imported as mirrors')
 for slot=1,6 do M[slot]=(Mirror(PA,slot) or {}).id end
 local own=true
 for slot=1,6 do own=own and M[slot]~=nil and CB(PA).IsOwnBuild(M[slot])==true end
 C.setup(own,'S0: fixture: every mirror is the character\'s own')
 -- The other peer's login Sync is answered while this peer is Automatic.
 Advance(30)
end)

C.scenario('S1 Automatic: the confirmed Share is the explicit operation; one summary',function()
 local r=Share(PA,M[1],TITLES[1],'S1')
 if not r then return end
 r1=r
 C.setup(LocallySaved(r),'S1: fixture: the listing was saved with the mirror\'s publication',printable(r.id))
 Until(function() return Pair.Full(B,r.id)~=nil end,1200)
 local sums,bad,contextual=Summaries(PA,r.id,r.sent)
 print('OBSERVED','S1 summaries',SummaryText(sums,bad,contextual))
 C.guard(#sums==1 and bad==0 and IdentityOf(sums[1].data,r.listing) and EchoFree(sums[1].data),
  'S1: Automatic sends exactly one summary of the listing, with its identity and no Echo list',SummaryText(sums,bad,contextual))
 local computed=SummaryBytes(PA,r.listing)
 C.setup(sums[1]~=nil and computed==sums[1].bytes,
  'S1: fixture: the summary size recomputed from the stored listing equals the actual wire size (used for S3)',
  printable(computed)..' / '..printable(sums[1] and sums[1].bytes))
 local adm=r.admission
 C.expect(adm~=nil and adm.queued==true and adm.route=='EnqueueControl' and adm.m.queueClass=='share'
  and adm.m.operationKind=='share' and adm.m.operationKey~=nil and adm.chunks==1,
  'S1: it is admitted as the explicit Share operation, one entry, not an untracked bulk summary',AdmissionText(adm))
 C.expect(r.line~=nil and r.line:find(r.title,1,true)~=nil and r.line:find('queued its summary',1,true)~=nil
  and r.line:find('not confirmed',1,true)~=nil,
  'S1: the completion line states the local save and the queued summary, not sending or receipt',r.line)
 C.guard(Pair.Full(B,r.id)~=nil,'S1: the other peer stores the listing with its Echo list after the summary')
 local exact,other=DpsHandoffs(PA,r.dps,r.id)
 C.guard(exact==1 and other==0,'S1: the DPS-best hand-off is one call with the listing ID only',exact..'/'..other)
end)

local r2
C.scenario('S2 explicit-choice Manual: one admitted summary, answered for the fetching peer until its own deadline',function()
 local policy=A.e.Nexus.SyncModePolicy
 local ok,result=policy.ApplyChoice('manual')
 C.setup(ok==true and policy.Mode()=='manual' and (policy.Choice() or {}).explicit=='manual',
  'S2: fixture: the explicit choice Manual is applied through ApplyChoice',printable(result))
 Advance(10)
 local idle=#A.H.sent
 Advance(20)
 C.guard(#A.H.sent==idle,'S2: under the chosen Manual, idle background work sends nothing',#A.H.sent-idle)
 local bytes=ModeBytes(PA)
 -- Viewing the mirror and a cancelled confirmation have no authority.
 local before,seq=#A.H.sent,PA.seq
 local popup=Confirm(PA,M[2],'S2 cancel')
 if popup then A.e.StaticPopup_Hide(DIALOG) end
 Advance(10)
 C.guard(popup~=nil and #A.H.sent==before and QueuedSince(PA,seq,nil)==nil,
  'S2: viewing the mirror and cancelling its confirmation queue and send nothing',(#A.H.sent-before)..' sent')
 local r=Share(PA,M[2],TITLES[2],'S2')
 if not r then return end
 r2=r
 C.setup(LocallySaved(r),'S2: fixture: the listing was saved with the mirror\'s publication',printable(r.id))
 local adm=r.admission
 local deadline=adm and tonumber(adm.m.expiresAt)
 C.expect(adm~=nil and adm.queued==true and adm.route=='EnqueueControl' and adm.m.queueClass=='share'
  and adm.m.operationKind=='share' and adm.m.operationKey~=nil and adm.chunks==1 and deadline~=nil
  and math.abs(deadline-(tonumber(adm.m.enqueuedAt) or 0)-SHARE_AGE)<1e-6,
  'S2: after the local commit, Manual admits this Share as the explicit Share operation: one summary entry with its own 120-second deadline',
  AdmissionText(adm))
 C.expect(r.line~=nil and r.line:find(r.title,1,true)~=nil and r.line:find('queued its summary',1,true)~=nil
  and r.line:find('not confirmed',1,true)~=nil,
  'S2: the completion line states the local save and the queued summary, and that sending and receipt are not confirmed',r.line)
 -- The same approval accepted again (its own dialog handler and data, as
 -- ux_share_confirmation S7): no second Share.
 local calls,mark,stamp=#PA.admissions,#PA.said,r.listing and r.listing.lastModified
 A.e.StaticPopupDialogs[DIALOG].OnAccept(r.popup.frame,r.popup.data)
 local again=A.e.Nexus.BuildCatalog.Get(r.id)
 C.guard(#PA.admissions==calls and Completion(PA,mark)==nil and type(again)=='table' and again.lastModified==stamp,
  'S2: the same approval accepted again starts no second Share')
 deadline=Followups(PA,B,r,'S2')
 -- During this Share, a fetch for another listing whose own Share window
 -- has ended is not answered (the permission is per listing and deadline).
 if r1 and r1.id then
  local due1=r1.admission and r1.admission.m.queueClass=='share' and tonumber(r1.admission.m.expiresAt) or (r1.at+SHARE_AGE)
  Until(function() return A.H.now>=due1+1 end,math.max(0,math.floor((due1+1-A.H.now)/.05)+2))
  local open=deadline==nil or A.H.now<deadline-12
  C.setup(open,'S2: fixture: the other listing\'s window ended inside this Share\'s window',printable(A.H.now)..' / '..printable(deadline))
  if open then
   local since=#A.H.sent
   Fetch(PA,r1.id,'OtherPeer')
   Advance(10)
   C.guard(not SentAbout(PA,r1.id,since),'S2: during this Share, a fetch for another listing (its own Share ended) is not answered')
  end
 end
 Expiry(PA,r,deadline,'S2')
 local codes,unexpected=Codes(PA,r.sent),{}
 for _,code in ipairs(codes) do if not ({WLBI=true,WLLC=true,WLRB=true})[code] then unexpected[#unexpected+1]=code end end
 C.guard(#unexpected==0,'S2: under Manual only this Share\'s summary and its answers left this client',table.concat(unexpected,','))
 C.guard(ModeBytes(PA)==bytes,'S2: the Share changes no stored Sync mode bytes (explicit choice, old syncMode, format marker)',
  bytes..' -> '..ModeBytes(PA))
 local exact,other=DpsHandoffs(PA,r.dps,r.id)
 C.guard(exact==1 and other==0,'S2: the DPS-best hand-off is one call with the listing ID only',exact..'/'..other)
 local status=A.e.Nexus.Sync.GetShareStatus(r.id)
 print('OBSERVED','S2 Sync share record',StatusText(status),'status text='..printable(select(2,CB(PA).ShareStatusText(r.id))))
end)

C.scenario('S3 explicit-choice Manual: an oversize summary is a final, visible refusal after the local save',function()
 local r=Share(PA,M[3],TITLES[3],'S3')
 if not r then return end
 local size=SummaryBytes(PA,r.listing)
 print('OBSERVED','S3 summary escaped bytes='..printable(size)..' budget='..BUDGET)
 C.setup(size~=nil and size>BUDGET,'S3: fixture: this listing\'s summary, recomputed as S1 verified against the wire, is over the line budget',printable(size))
 C.guard(LocallySaved(r),'S3: the listing and the mirror\'s publication were saved locally',printable(r.id))
 C.expect(r.line~=nil and r.line:find(LONG,1,true)~=nil and r.line:find('not queued',1,true)~=nil
  and r.line:find('summary too large',1,true)~=nil and r.line:find('nothing was sent',1,true)~=nil
  and r.line:find('queued its summary',1,true)==nil,
  'S3: the completion line states the final size refusal after the local save, not a queued claim',r.line)
 local status=r.id and A.e.Nexus.Sync.GetShareStatus(r.id) or nil
 C.expect(status~=nil and status.id==r.id and status.terminal==true and status.queueAdmitted~=true
  and status.reason=='summary too large',
  'S3: Sync\'s own record of this explicit Share is that final refusal',StatusText(status))
 Advance(20)
 local sums,bad=Summaries(PA,r.id,r.sent)
 C.guard(#sums==0 and bad==0 and QueuedSince(PA,r.seq,r.id)==nil,'S3: nothing of it is queued or sent',#sums..' sent')
 local exact,other=DpsHandoffs(PA,r.dps,r.id)
 C.guard(exact==1 and other==0,'S3: the DPS-best hand-off is one call with the listing ID only',exact..'/'..other)
end)

C.scenario('S4 explicit-choice Manual, then Off before submission: the final-submit check drops the queued summary',function()
 local r=Share(PA,M[4],TITLES[4],'S4',function() A.H.combat=true end)
 if not r then A.H.combat=false;return end
 local adm=r.admission
 C.expect(adm~=nil and adm.queued==true and adm.m.queueClass=='share' and adm.m.operationKind=='share',
  'S4: the confirmed Share is admitted under Manual while combat holds the wire',AdmissionText(adm))
 local policy=A.e.Nexus.SyncModePolicy
 local sent0,eventMark=#A.H.sent,PA.seq
 local ok,result=policy.ApplyChoice('off')
 C.setup(ok==true and policy.Mode()=='off','S4: fixture: the explicit choice Off is applied while the summary waits',printable(result))
 C.guard(#A.H.sent==sent0,'S4: applying Off sends nothing by itself')
 A.H.combat=false
 Advance(20)
 local drop
 for _,e in ipairs(PA.events) do
  if e.n>eventMark and e.kind=='send_dropped' and r.id and e.m.buildId==r.id then drop=drop or e end
 end
 local status=r.id and A.e.Nexus.Sync.GetShareStatus(r.id) or nil
 print('OBSERVED','S4 drop','reason='..printable(drop and drop.reason),'at='..printable(drop and drop.at),
  'deadline='..printable(adm and adm.m.expiresAt),'record',StatusText(status),
  'modeDropped='..printable(A.e.Nexus.Sync.Stats().modeDropped))
 C.expect(adm~=nil and adm.queued==true and drop~=nil and policy.IsModeReason(drop.reason)==true
  and drop.at<(tonumber(adm.m.expiresAt) or -math.huge)
  and status~=nil and status.terminal==true and status.sendCompleted~=true and policy.IsModeReason(status.reason)==true,
  'S4: the waiting Share ends at the final-submit check with the saved-mode reason, before its deadline, and is never sent',
  printable(drop and drop.reason))
 local sums=Summaries(PA,r.id,r.sent)
 C.guard(#sums==0,'S4: no summary of it left this client',#sums)
end)

C.scenario('S5 explicit-choice Off: the Share is saved locally, refused at admission, and nothing is sent',function()
 local policy=A.e.Nexus.SyncModePolicy
 C.setup(policy.Mode()=='off' and (policy.Choice() or {}).explicit=='off','S5: fixture: the explicit choice is Off')
 local r=Share(PA,M[5],TITLES[5],'S5')
 if not r then return end
 C.guard(r.note:find('Your saved Sync mode is Off',1,true)~=nil,'S5: the confirmation says the listing is saved and not sent under Off',r.note)
 C.guard(LocallySaved(r),'S5: the listing and the mirror\'s publication were saved locally',printable(r.id))
 C.guard(r.line~=nil and r.line:find('not sent: your saved Sync mode is Off.',1,true)~=nil and r.line:find('queued its summary',1,true)==nil,
  'S5: the completion line states the exact Off result',r.line)
 local refused,queued=0,0
 for _,a in ipairs(PA.admissions) do
  if a.n>r.seq and r.id and a.m.buildId==r.id then
   if a.queued==true then queued=queued+1 elseif policy.IsModeReason(a.why) then refused=refused+1 end
  end
 end
 C.guard(refused>=1 and queued==0,'S5: the summary is refused at queue admission by the saved mode; nothing is queued',refused..'/'..queued)
 local status=r.id and A.e.Nexus.Sync.GetShareStatus(r.id) or nil
 C.expect(status~=nil and status.id==r.id and status.terminal==true and status.queueAdmitted~=true
  and policy.IsModeReason(status.reason)==true and status.reason==policy.Text('off'),
  'S5: Sync\'s own record of this explicit Share is the final refusal with the Off reason',StatusText(status))
 local sent=#A.H.sent
 Advance(20)
 C.guard(#A.H.sent==sent,'S5: under Off nothing is sent',#A.H.sent-sent)
end)

C.scenario('S6 Sync unavailable: the line states it after the local save',function()
 local policy=A.e.Nexus.SyncModePolicy
 local ok,result=policy.ApplyChoice('automatic')
 C.setup(ok==true and policy.Mode()=='automatic','S6: fixture: the explicit choice Automatic is applied',printable(result))
 local S=A.e.Nexus.Sync
 local summary,build=S.BroadcastBuildSummary,S.BroadcastBuild
 local r=Share(PA,M[6],TITLES[6],'S6',function() S.BroadcastBuildSummary,S.BroadcastBuild=nil,nil end)
 S.BroadcastBuildSummary,S.BroadcastBuild=summary,build
 if not r then return end
 C.guard(LocallySaved(r),'S6: the listing and the mirror\'s publication were saved locally',printable(r.id))
 C.expect(r.line~=nil and r.line:find('not queued',1,true)~=nil and r.line:find('sync unavailable',1,true)~=nil
  and r.line:find('nothing was sent',1,true)~=nil and r.line:find('queued its summary',1,true)==nil,
  'S6: the completion line states that Sync was unavailable and nothing was queued or sent',r.line)
 Advance(10)
 local sums=Summaries(PA,r.id,r.sent)
 C.guard(#sums==0 and QueuedSince(PA,r.seq,r.id)==nil,'S6: nothing of it is queued or sent later (no automatic retry)',#sums..' sent')
 local exact,other=DpsHandoffs(PA,r.dps,r.id)
 C.guard(exact==1 and other==0,'S6: the DPS-best hand-off is one call with the listing ID only',exact..'/'..other)
 C.guard(#A.H.actions==0,'S6: no game action in this runtime',#A.H.actions)
end)

C.scenario('L1 accepted legacy Manual (format 5, no explicit choice): admitted, answered, then expired',function()
 local A2,B2=Pair.Boot({'SharePeer','OtherPeer'},{5,8},function(i,db)
  if i~=1 then return end
  db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode='manual'
 end,{slots={[1]=Slots({[1]='Admission Legacy'})}})
 local P2=Open(A2);live={P2}
 local policy=A2.e.Nexus.SyncModePolicy
 C.setup(policy.Mode()=='manual' and (policy.Choice() or {}).explicit==nil,
  'L1: fixture: the accepted format-5 Manual applies with no explicit choice')
 C.setup(Record(P2),'L1: fixture: the pass-through recorders are installed')
 local bytes=ModeBytes(P2)
 CB(P2).Show()
 C.setup(Until(function() return Mirror(P2,1)~=nil and Ready(P2) end,4000)~=nil,'L1: fixture: the Saved Build is imported as a mirror')
 local mirrorId=(Mirror(P2,1) or {}).id
 Advance(10)
 local idle=#A2.H.sent
 Advance(10)
 C.guard(#A2.H.sent==idle,'L1: legacy Manual idle sends nothing',#A2.H.sent-idle)
 local r=Share(P2,mirrorId,'Admission Legacy','L1')
 if not r then return end
 C.setup(LocallySaved(r),'L1: fixture: the listing was saved with the mirror\'s publication',printable(r.id))
 local adm=r.admission
 local deadline=adm and tonumber(adm.m.expiresAt)
 C.expect(adm~=nil and adm.queued==true and adm.route=='EnqueueControl' and adm.m.queueClass=='share'
  and adm.m.operationKind=='share' and adm.chunks==1 and deadline~=nil
  and math.abs(deadline-(tonumber(adm.m.enqueuedAt) or 0)-SHARE_AGE)<1e-6,
  'L1: legacy Manual admits this Share as the explicit Share operation with its own 120-second deadline',AdmissionText(adm))
 C.expect(r.line~=nil and r.line:find('queued its summary',1,true)~=nil and r.line:find('not confirmed',1,true)~=nil,
  'L1: the completion line states the local save and the queued summary, not sending or receipt',r.line)
 deadline=Followups(P2,B2,r,'L1')
 Expiry(P2,r,deadline,'L1')
 local codes,unexpected=Codes(P2,r.sent),{}
 for _,code in ipairs(codes) do if not ({WLBI=true,WLLC=true,WLRB=true})[code] then unexpected[#unexpected+1]=code end end
 C.guard(#unexpected==0,'L1: under Manual only this Share\'s summary and its answers left this client',table.concat(unexpected,','))
 C.guard(ModeBytes(P2)==bytes and A2.e.NexusDB.settings.syncMode=='manual' and A2.e.NexusDB.settingsVersion==5
  and (policy.Choice() or {}).explicit==nil,
  'L1: the Share changes no stored Sync mode bytes; the legacy Manual stays without an explicit choice',bytes..' -> '..ModeBytes(P2))
 local exact,other=DpsHandoffs(P2,r.dps,r.id)
 C.guard(exact==1 and other==0,'L1: the DPS-best hand-off is one call with the listing ID only',exact..'/'..other)
 C.guard(#A2.H.actions==0,'L1: no game action in this runtime',#A2.H.actions)
end)

C.finish('(a confirmed own Saved Build Share is the explicit Share operation: its actual admission or final refusal is stated after the local save, and answers follow only until its own deadline)')
