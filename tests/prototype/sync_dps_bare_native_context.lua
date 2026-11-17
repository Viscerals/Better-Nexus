-- Synthetic bare native-context regression; no real account/game/network proof.
-- Actual first RequestSync and captured production egress must reach exact public
-- getters/board with genuine native provenance, preserving unknown-route refusal.
local P=dofile('tests/prototype/sync_pair_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
math.randomseed(1)
local checks=0
local function check(ok,why) assert(ok,why);checks=checks+1 end
local function run(enabled,cfg)
math.randomseed(1)
P.Boot({'Origin','Recipient'},0,function(i,db)
 if i==2 then
  db.settingsVersion=5;db.accountCharacters={}
  db.settings.syncMode='manual'
 end
end,{realm='Rogue-Lite (Live)',realmApis={
 {game='Rogue-Lite (Live)',normalized=cfg.sourceShim and 'RogueLite(Live)' or 'Rogue-Lite (Live)'},
 {game='Rogue-Lite (Live)',normalized=cfg.receiverShim and 'RogueLite(Live)' or 'Rogue-Lite (Live)'}}})
local source,receiver=P.A,P.B
for _,p in ipairs({source,receiver}) do
 p.name=p.e.UnitName('player')..'-rogue-lite(live)'
end
local N=source.e.Nexus
local echoes={{spellId=200001,count=3},{spellId=200002,count=1}}
local row={v=7,p='Origin',o='origin@rogue-lite(live)',r='rogue-lite(live)',
 k='MAGE',l=80,c='lk',d=47000,u=134.612,t=1700000900,e=echoes,
 f=N.DpsCapture.GetEchoKey(echoes),h=N.DpsCapture.GetEchoHash(echoes),
 lk={{spellId=200085,count=1}}}
local encoded=N.Codec.Base64Encode(N.Codec.JSONEncode(row))
local total=math.ceil(#encoded/100)
for i=1,total do
 P.Channel(source,string.format('WLD2|Origin|fixture-lk:1700000900:47000|%d/%d|%s',
  i,total,encoded:sub((i-1)*100+1,i*100)),source.name)
end
local function advance(seconds)
 for _=1,math.floor(seconds/.05+.5) do
  source.H.Advance(.05,.05);receiver.H.Advance(.05,.05)
 end
end
advance(25)
local syntheticRow=assert(N.DpsCapture.GetCharacterBest('lk','Origin',row.o))
local seedStart=#source.H.sent
check(N.Sync.BroadcastBuild(assert(N.BuildCatalog.Get(syntheticRow.buildId)))==true,
 'public synthetic catalog seed accepted')
advance(15)
local seeded=0
local function wire(packet) return packet.text:gsub('||','|'):gsub('^P%d+:','') end
for i=seedStart+1,#source.H.sent do
 local packet=source.H.sent[i]
 if wire(packet):match('^WLRB|') then
  P.Channel(receiver,packet.text,source.name);seeded=seeded+1
 end
end
advance(10)
check(seeded>0 and receiver.e.Nexus.BuildCatalog.Get(syntheticRow.buildId)~=nil,
 'captured public build egress established receiver page')
check(receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin',row.o)==nil,
 'receiver has no synthetic LK record before measured request')
if cfg.legacyReceiver then
 for i=1,total do
  receiver.e.Nexus.Sync.HandleIncoming(string.format(
   'WLD2|Origin|fixture-legacy:1700000900:47000|%d/%d|%s',
   i,total,encoded:sub((i-1)*100+1,i*100)),'Origin')
 end
 local old=receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin')
 check(old and old.dps==row.d and old.ts==row.t
  and receiver.e.Nexus.DpsCapture.VerifiedOwnerKey(old)==nil,
  'synthetic unknown-route same-score receiver baseline remains unverified')
 advance(5)
 old=receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin')
 check(old and old.dps==row.d and old.ts==row.t and old.duration==row.u
  and old.fingerprint==row.f and receiver.e.Nexus.DpsCapture.VerifiedOwnerKey(old)==nil,
  'idle receiver work cannot invent authority for historical score')
end
local saved=F.Serialize(source.e.NexusDB.authorityBundle.dpsCapture)
for _,p in ipairs({source,receiver}) do
 p.cursor=#p.H.sent
 if enabled then check(p.e.Nexus.PeerDebug.Start()==true,'bounded trace started')
 else p.e.Nexus.PeerDebug.Clear() end
end
local requestId
local transfers,responsePackets={},{}
local captured,traffic,rawTraffic=0,{},{}
local receiverBefore=F.Serialize(receiver.e.NexusDB.authorityBundle.dpsCapture.characterBest)
local faultTransfers={}
local faultDelivered=0
local function deliverFault(packet,text,actualSender)
 check(packet.route=='chat' and packet.kind=='CHANNEL','fault uses actual captured native egress')
 local declared,transfer,index,count,data,requester,id,bucket=text:match(
  '^WLD2|([^|]+)|([^|]+)|(%d+)/(%d+)|([^|]+)|([^|]+)|([^|]+)|(%d+)$')
 check(transfer and id==requestId,'completed fault retains actual first request transfer')
 index,count,bucket=tonumber(index),tonumber(count),tonumber(bucket)
 local held=faultTransfers[transfer]
 if not held then
  held={chunks={},received=0,size=0,count=count,requester=requester,id=id,bucket=bucket}
  faultTransfers[transfer]=held
 end
 check(held.count==count and held.requester==requester and held.id==id
  and held.bucket==bucket,'all captured original chunks agree on the same context')
 if not held.chunks[index] then held.received=held.received+1 end
 held.chunks[index]=data;held.size=math.max(held.size,#data)
 if held.received~=held.count or held.delivered then return end
 held.delivered=true
 local original=assert(N.Codec.JSONDecode(N.Codec.Base64Decode(table.concat(held.chunks))))
 check(original.p=='Origin' and original.d==row.d and original.t==row.t
  and original.o==row.o and original.x==nil,'fault source is actual captured direct-owner fixture payload')
 local changed=assert(N.Codec.JSONDecode(N.Codec.JSONEncode(original)))
 if cfg.payloadFault=='schema' then changed.v='offline-invalid-version'
 elseif cfg.payloadFault=='owner_context' then
  changed.x={n=requester,i=id,b=bucket}
 elseif cfg.payloadFault=='integrity' then changed.f='offline-fingerprint-mismatch'
 else error('unknown completed payload fault') end
 if cfg.foreignRequester then requester='Recipient-OtherRealm' end
 local encodedFault=N.Codec.Base64Encode(N.Codec.JSONEncode(changed))
 local parts=math.ceil(#encodedFault/held.size)
 for part=1,parts do
  local delivered=string.format('WLD2|%s|%s|%d/%d|%s|%s|%s|%d',
   declared,transfer,part,parts,encodedFault:sub((part-1)*held.size+1,part*held.size),requester,id,bucket)
  if cfg.route=='unknown' then receiver.e.Nexus.Sync.HandleIncoming(delivered,actualSender)
  else
   if cfg.missingRealm then receiver.e.GetRealmName=nil end
   P.Channel(receiver,delivered,actualSender)
  end
 end
 faultDelivered=faultDelivered+1
end
local function pump(p,q)
 while p.cursor<#p.H.sent do
  p.cursor=p.cursor+1
  local packet=p.H.sent[p.cursor]
  local rawEvent={peer=p.name,text=packet.text,route=packet.route,
   kind=packet.kind,target=packet.target,prefix=packet.prefix}
  rawTraffic[#rawTraffic+1]=rawEvent
  local comparisonText=packet.text
  -- The unrelated WLCP session token varies between fresh runtimes. Keep
  -- raw bytes above; compare only that opaque final token canonically. All
  -- request, claim and DPS packet bytes/IDs remain untouched in this check.
  if wire(packet):match('^WLCP|') then
   comparisonText=wire(packet):gsub('^(WLCP|[^|]+|[^|]+|)[^|]+$','%1<opaque-session-token>')
  end
  traffic[#traffic+1]={peer=p.name,text=comparisonText,route=packet.route,
   kind=packet.kind,target=packet.target,prefix=packet.prefix}
  local text=wire(packet)
  if p==receiver and text:match('^WLRQ|') and not requestId then
   requestId=text:match('^WLRQ|[^|]+|[^|]+|[^|]+|([^|]+)')
  end
  if p==source and text:match('^WLD2|') then
   local transfer,requester,id,bucket=text:match(
    '^WLD2|[^|]+|([^|]+)|[^|]+|[^|]+|([^|]+)|([^|]+)|(%d+)$')
   if transfer then
    transfers[transfer]={requester=requester,requestId=id,bucket=tonumber(bucket)}
    responsePackets[#responsePackets+1]={packet=packet,requestId=id}
    captured=captured+1
   end
  end
  if cfg.payloadFault and p==source and text:match('^WLD2|') then
   deliverFault(packet,text,cfg.qualified and p.name or p.e.UnitName('player'))
  elseif packet.route=='chat' then
   local sender=cfg.qualified and p.name or p.e.UnitName('player')
   local delivered=packet.text
   if p==source and text:match('^WLD2|') then
    sender=cfg.actualSource or sender
    if cfg.missingRealm then q.e.GetRealmName=nil end
    if cfg.otherNativeRealm then q.e.GetRealmName=function() return 'OtherRealm' end end
    if cfg.wrongBucket then
     delivered=text:gsub('|(%d+)$',function(b) return '|'..tostring(tonumber(b)%8+1) end)
    elseif cfg.foreignRequester then
     delivered=text:gsub('|Recipient|','|Recipient-OtherRealm|')
    elseif cfg.foreignId then
     delivered=text:gsub(requestId:gsub('(%W)','%%%1'),'c1-unrelated')
     check(delivered~=text,'control changes exact captured request ID only')
    end
    if cfg.route=='unknown' then q.e.Nexus.Sync.HandleIncoming(delivered,sender)
    else P.Channel(q,delivered,sender) end
   else P.Channel(q,delivered,sender) end
  elseif packet.route=='addon' and (packet.kind~='WHISPER'
   or packet.target==q.name or packet.target==q.e.UnitName('player')) then
   q.H.Fire('CHAT_MSG_ADDON',packet.prefix,packet.text,packet.kind,p.name)
  end
 end
end
check(receiver.e.Nexus.Sync.RequestSync()==true,'real manual RequestSync accepted')
for _=1,800 do
 source.H.Advance(.05,.05);receiver.H.Advance(.05,.05)
 pump(receiver,source);pump(source,receiver)
end
check(type(requestId)=='string' and requestId:match('^c1%-'),
 'actual request ID retained from captured production wire')
check(captured>0,'actual contextual DPS egress captured')
if cfg.payloadFault then
 local state=receiver.e.Nexus.Sync.Stats()
 print('FAULT_OBSERVED '..cfg.label..' id='..tostring(state.requestId)
  ..' rejected='..tostring(state.requestRejected)..' unrelated='..tostring(state.requestUnrelated)
  ..' reason='..tostring(state.requestLastReason))
 check(faultDelivered==1,'one actual completed production transfer was fault-delivered')
 check(state.requestId==requestId and state.useful==false and state.requestUpdated==0,
  'completed rejection retains actual current request without useful progress')
 if cfg.unrelatedFault then
  check(state.requestRejected==0 and state.requestUnrelated==1,
   'nonnative/foreign completed refusal cannot gain local rejection attribution')
 else
  check(state.requestRejected==1 and state.requestUnrelated==0,
   'completed native refusal counts rejection against exact current ID: '..cfg.label)
  check(state.requestLastReason==cfg.expectedReason,
   'completed native refusal keeps exact standardized reason')
 end
 check(state.dpsDirectAccepted==0 and state.dpsRelayAccepted==0,
  'completed payload refusal admits no direct or relay score')
 if cfg.receiveReason then
  check(receiver.e.Nexus.DpsCapture.RejectionStats()[cfg.receiveReason]==1,
   'downstream receive control preserves original scalar rejection reason')
 end
 check(F.Serialize(receiver.e.NexusDB.authorityBundle.dpsCapture.characterBest)==receiverBefore,
  'completed payload refusal leaves whole canonical receiver score store unchanged')
 check(F.Serialize(source.e.NexusDB.authorityBundle.dpsCapture)==saved,
  'completed payload fault leaves source evidence unchanged')
 local observed=false
 for _,event in ipairs(receiver.e.Nexus.PeerDebug.Events()) do
  local f=event.fields
  if (event.kind=='dps_validation' or event.kind=='dps_commit')
   and f.requestId==requestId and f.outcome=='rejected'
   and transfers[f.transferId] and f.bucket==transfers[f.transferId].bucket then observed=true end
 end
 check(observed,'completed refusal diagnostic retains exact captured ID/transfer/bucket')
 check(#source.H.actions==0 and #receiver.H.actions==0,'completed fault has zero game actions')
 print('PASS completed-context fault '..cfg.label..' checks='..checks)
 return
end
if cfg.reject or cfg.foreignRequester or cfg.foreignId then
 local score=receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin',row.o)
 local state=receiver.e.Nexus.Sync.Stats()
 if cfg.reject then
  check(score==nil,'invalid native/nonnative context cannot admit owner score: '..cfg.label)
  check(state.dpsDirectAccepted==0 and state.dpsRelayAccepted==0,
   'refused route cannot promote direct or relay acceptance: '..cfg.label)
 else
  -- Existing direct-owner policy may store an authenticated ambient record.
  -- A foreign request tuple cannot gain local progress/window ownership.
  check(score and score.dps==row.d,'authenticated owner ambient record still follows existing policy')
  check(state.requestId==requestId and state.useful==false and state.requestUpdated==0
   and state.requestUnrelated>0,'foreign requester/ID cannot gain current request progress')
 end
 check(F.Serialize(source.e.NexusDB.authorityBundle.dpsCapture)==saved,
  'negative context leaves source evidence unchanged')
 check(#source.H.actions==0 and #receiver.H.actions==0,'negative context has zero game actions')
 print('PASS native-context control '..cfg.label..' checks='..checks)
 return
end
local sourceEvents=N.PeerDebug.Events()
local receiverEvents=receiver.e.Nexus.PeerDebug.Events()
local function found(events,kind,id,transfer,outcome)
 for _,event in ipairs(events) do local f=event.fields
  if event.kind==kind and f.requestId==id
   and (not transfer or f.transferId==transfer)
   and (not outcome or f.outcome==outcome) then return f end
 end
end
local function outcomeCounters(sync)
 local stats=sync.Stats()
 local projected={}
 -- Outcome/egress counters, not nondeterministic maintenance scan work.
 for _,key in ipairs({'dpsRequestsReceived','dpsRelayOffered','dpsDirectAccepted',
  'dpsDirectRejected','dpsRelayAccepted','dpsRelayRejected','admittedPackets',
  'admittedBytes','attempted','sent','received','storageRejected',
  'requestNew','requestUpdated','requestRejected','requestDuplicates'}) do
  projected[key]=stats[key]
 end
 return F.Serialize(projected)
end
local result={traffic=F.Serialize(traffic),rawTraffic=F.Serialize(rawTraffic),
 source=F.Serialize(source.e.NexusDB.authorityBundle.dpsCapture),
 receiver=F.Serialize(receiver.e.NexusDB.authorityBundle.dpsCapture),
 sourceStats=outcomeCounters(N.Sync),
 receiverStats=outcomeCounters(receiver.e.Nexus.Sync)}
if not enabled then
 check(#sourceEvents==0 and #receiverEvents==0,'disabled trace collects no events')
 check(#source.H.actions==0 and #receiver.H.actions==0,'disabled case has zero game actions')
 return result
end
check(receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin',row.o)~=nil,'bare native first-request durable owner admission')
check(found(sourceEvents,'request_scheduled',requestId)~=nil,'actual scheduled request exact ID observed')
check(found(receiverEvents,'send_attempted',requestId)~=nil,'request send exact ID observed')
local accepted=0
for transfer,context in pairs(transfers) do
 if context.requestId==requestId then
  local offered=found(sourceEvents,'dps_offer',requestId,transfer,'admitted')
  local sent=found(sourceEvents,'send_attempted',requestId,transfer)
  local assembled=found(receiverEvents,'dps_transfer_complete',requestId,transfer,'complete')
  local committed=found(receiverEvents,'dps_commit',requestId,transfer,'accepted')
  for _,fields in ipairs({assert(offered),assert(sent),assert(assembled),assert(committed)}) do
   check(fields.requester==context.requester and fields.bucket==context.bucket
    and fields.dataKind=='D','exact wire context propagated through real observation seam')
  end
  check(committed.relay==false,'accepted diagnostic retains direct/relay boolean')
  accepted=accepted+1
 end
end
check(accepted>0,'original manual request has actual accepted contextual transfer')
local received=receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin',row.o)
check(received and received.dps==row.d and received.ownerVerified==true,
 'real durable synthetic admission agrees with diagnostic commit')
local named=receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin')
local displayed=false
for _,b in ipairs(receiver.e.Nexus.DpsCapture.GetDpsBoard('lk') or {}) do
 if b.dps==row.d and b.ownerKey==row.o and b.ownerVerified==true then displayed=true end
end
check(named and named.dps==row.d and named.ts==row.t and named.duration==row.u
 and named.fingerprint==row.f and receiver.e.Nexus.DpsCapture.VerifiedOwnerKey(named)==row.o
 and displayed,'bare native first request appears in named getter/public board')
local progress=receiver.e.Nexus.Sync.Stats()
check(progress.requestId==requestId and progress.useful==true and progress.requestUpdated>0
 and progress.requestLastReason=='accepted','native requester progress attributed to actual first request')
local direct=found(receiverEvents,'dps_commit',requestId,nil,'accepted')
check(direct.senderForm==(cfg.qualified and 'qualified' or 'bare')
 and direct.nativeOwnerContext==not cfg.qualified,'bounded trace preserves original event sender form')

check(F.Serialize(source.e.NexusDB.authorityBundle.dpsCapture)==saved,
 'diagnostic request left source scores and record metadata unchanged')
-- Explicit offline fault injection: change only the captured envelope bucket
-- to a different valid bucket. Existing request authorization must refuse;
-- diagnostics must keep the actual supplied envelope IDs, not a current ID.
advance(100)
receiver.e.Nexus.PeerDebug.Start()
local replayed
for _,capturedResponse in ipairs(responsePackets) do
 if capturedResponse.requestId==requestId then
  local corrupted=wire(capturedResponse.packet):gsub('|(%d+)$',function(bucket)
   return '|'..tostring(tonumber(bucket)%8+1)
  end)
  P.Channel(receiver,corrupted,source.name);replayed=true
 end
end
check(replayed,'captured response replay available')
local rejected=found(receiver.e.Nexus.PeerDebug.Events(),'dps_commit',requestId,nil,'rejected')
check(rejected and rejected.reason=='outside requested response'
 and transfers[rejected.transferId]~=nil,'request authorization refusal keeps exact captured ID and transfer')
check(#source.H.actions==0 and #receiver.H.actions==0,'zero harness gameplay actions')
if cfg.legacyReceiver then
 local serialized=F.Serialize(receiver.e.NexusDB)
 receiver.e.NexusDB=assert(loadstring('return '..serialized))()
 receiver=P.Rejoin(2)
 advance(15)
 local durable=receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin',row.o)
 local shown=receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin')
 check(durable and shown and durable.dps==row.d and durable.ts==row.t
  and durable.duration==row.u and durable.fingerprint==row.f
  and receiver.e.Nexus.DpsCapture.VerifiedOwnerKey(durable)==row.o
  and shown.dps==row.d and shown.ts==row.t and shown.duration==row.u
  and shown.fingerprint==row.f and receiver.e.Nexus.DpsCapture.VerifiedOwnerKey(shown)==row.o,
  'serialized reload preserves exact same-score native promotion and public getter')
 local persistedBoard=false
 for _,b in ipairs(receiver.e.Nexus.DpsCapture.GetDpsBoard('lk') or {}) do
  if b.dps==row.d and b.ts==row.t and b.ownerKey==row.o and b.ownerVerified==true then
   persistedBoard=true
  end
 end
 check(persistedBoard,'serialized reload retains same-score verified public LK board')
 check(F.Serialize(source.e.NexusDB.authorityBundle.dpsCapture)==saved
  and #source.H.actions==0 and #receiver.H.actions==0,
  'synthetic reload leaves source evidence unchanged and has zero game actions')
end
print('PASS sync_dps_bare_native_context checks='..checks..'; contextual chunks='..captured)
return result
end
local completedFaults={
 {label='native schema',payloadFault='schema',expectedReason='schema'},
 {label='native direct owner with relay context',payloadFault='owner_context',expectedReason='ownership'},
 {label='native integrity commit',payloadFault='integrity',expectedReason='storage',receiveReason='integrity'},
 {label='qualified native schema',payloadFault='schema',qualified=true,expectedReason='schema'},
 {label='qualified native owner context',payloadFault='owner_context',qualified=true,expectedReason='ownership'},
 {label='unknown bare schema',payloadFault='schema',route='unknown',unrelatedFault=true},
 {label='unknown bare owner context',payloadFault='owner_context',route='unknown',unrelatedFault=true},
 {label='foreign requester schema',payloadFault='schema',foreignRequester=true,unrelatedFault=true},
 {label='foreign requester owner context',payloadFault='owner_context',foreignRequester=true,unrelatedFault=true},
}
if arg and arg[1] then
 local selected=tonumber(arg[1]);assert(selected and completedFaults[selected],'unknown fault probe selection')
 run(true,completedFaults[selected]);return
end
local cfg={}
-- The matched pair must run the same simulated schedule. run() reseeds
-- math.random; the default harness profiler (debugprofilestop) reads real CPU
-- time and paces startup slices, so the cold first boot could finish one 0.05 s
-- update later and its request ID (from GetTime) differ. The supported
-- one-slice-per-update pacing holds that input matched for both runs only.
local restorePacing=dofile('tests/prototype/startup_support.lua').SingleSlicePacing()
local off=run(false,cfg)
local on=run(true,cfg)
restorePacing()
for _,field in ipairs({'traffic','source','receiver','sourceStats','receiverStats'}) do
 if off[field]~=on[field] then
  local at=1
  while at<=#off[field] and off[field]:sub(at,at)==on[field]:sub(at,at) do at=at+1 end
  print('OFFLINE MISMATCH '..field..' byte='..at..' off='..off[field]:sub(math.max(1,at-140),at+60)..' on='..on[field]:sub(math.max(1,at-140),at+60))
 end
 check(off[field]==on[field],'matched diagnostics off/on identical '..field)
end
print('PASS matched diagnostics on/off checks='..checks)
print('MATCHED WIRE: only unrelated WLCP opaque final token canonicalized; raw_equal='..tostring(off.rawTraffic==on.rawTraffic))

for _,case in ipairs({
 {qualified=true}, {sourceShim=true}, {receiverShim=true}, {sourceShim=true,receiverShim=true},
 {legacyReceiver=true},
}) do run(true,case) end
for _,case in ipairs({
 {label='unknown bare route',route='unknown',reject=true},
 {label='qualified foreign realm cannot own native claim',actualSource='Origin-OtherRealm',reject=true},
 {label='missing actual native realm',missingRealm=true,reject=true},
 {label='different actual native realm',otherNativeRealm=true,reject=true},
 {label='malformed actual native sender',actualSource='bad|name',reject=true},
 {label='wrong context bucket',wrongBucket=true,reject=true},
 {label='foreign qualified requester',foreignRequester=true},
 {label='unrelated valid request ID',foreignId=true},
}) do run(true,case) end
for _,case in ipairs(completedFaults) do run(true,case) end
local debug=P.B.e.Nexus.PeerDebug
debug.Start()
debug.Record('bad_sender_form',{senderForm='bare|payload',nativeOwnerContext='true'})
local fields=debug.Events()[2].fields
check(fields.senderForm==nil and fields.nativeOwnerContext==nil,
 'bounded sender form/provenance refuse arbitrary text and bool coercion')
debug.Record('owner_boundary',{senderForm='bare',nativeOwnerContext=true,directOwner=true})
fields=debug.Events()[3].fields
check(fields.directOwner==true and fields.senderForm==nil and fields.nativeOwnerContext==nil,
 'new sender diagnostics do not widen identifier-free owner boundary')
print('PASS synthetic bare/qualified/native realm-shim first-request contexts checks='..checks)
