-- Issue #171 review repair (Spec P1, sent-request settlement). A real manual
-- Sync request is sent before the pause. Its correlated contextual DPS answer,
-- held in transit across a Pause and Resume (quick, or with updates while
-- paused), still settles after Resume, inside its receive window, exactly as
-- unpaused. The old grant sends nothing more. A different request ID is still
-- refused. Two real runtimes over the pair harness; synthetic data only; the
-- setup is the public egress seeding of sync_dps_bare_native_context.
local P=dofile('tests/prototype/sync_pair_support.lua')
local failures={}
local function Case(name,fn)
 local ok,err=pcall(fn)
 print((ok and 'CASE PASS ' or 'CASE FAIL ')..name..(ok and '' or (': '..tostring(err))))
 if not ok then failures[#failures+1]=name end
end
local function wire(packet) return packet.text:gsub('||','|'):gsub('^P%d+:','') end

local function Run(mode,foreignId)
 math.randomseed(1)
 P.Boot({'Origin','Recipient'},0,function(i,db)
  if i==2 then db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode='manual' end
 end,{realm='Rogue-Lite (Live)'})
 local source,receiver=P.A,P.B
 for _,p in ipairs({source,receiver}) do p.name=p.e.UnitName('player')..'-rogue-lite(live)' end
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
  for _=1,math.floor(seconds/.05+.5) do source.H.Advance(.05,.05);receiver.H.Advance(.05,.05) end
 end
 advance(25)
 local syntheticRow=assert(N.DpsCapture.GetCharacterBest('lk','Origin',row.o))
 local seedStart=#source.H.sent
 assert(N.Sync.BroadcastBuild(assert(N.BuildCatalog.Get(syntheticRow.buildId)))==true,'setup: seed')
 advance(15)
 for i=seedStart+1,#source.H.sent do
  local packet=source.H.sent[i]
  if wire(packet):match('^WLRB|') then P.Channel(receiver,packet.text,source.name) end
 end
 advance(10)
 assert(receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin',row.o)==nil,'setup: no record before the request')
 for _,p in ipairs({source,receiver}) do p.cursor=#p.H.sent end
 local requestId
 local held={}
 local holding=true
 local function pump(p,q)
  while p.cursor<#p.H.sent do
   p.cursor=p.cursor+1
   local packet=p.H.sent[p.cursor];local text=wire(packet)
   if p==receiver and text:match('^WLRQ|') and not requestId then
    requestId=text:match('^WLRQ|[^|]+|[^|]+|[^|]+|([^|]+)')
   end
   if p==source and text:match('^WLD2|') and holding then
    held[#held+1]=packet
   elseif packet.route=='chat' then
    P.Channel(q,packet.text,p.e.UnitName('player'))
   elseif packet.route=='addon' and (packet.kind~='WHISPER'
    or packet.target==q.name or packet.target==q.e.UnitName('player')) then
    q.H.Fire('CHAT_MSG_ADDON',packet.prefix,packet.text,packet.kind,p.name)
   end
  end
 end
 local function step(n)
  for _=1,n do source.H.Advance(.05,.05);receiver.H.Advance(.05,.05);pump(receiver,source);pump(source,receiver) end
 end
 assert(receiver.e.Nexus.Sync.RequestSync()==true,'setup: real manual RequestSync accepted')
 for _=1,800 do step(1);if #held>0 and requestId then break end end
 step(40)
 assert(type(requestId)=='string' and requestId:match('^c1%-'),'setup: the request was actually sent')
 assert(#held>0,'setup: its contextual answer is in transit')
 local R=receiver.e.Nexus
 local sentBefore=#receiver.H.sent
 if mode=='quick' then R.SessionPause.Pause();R.SessionPause.Resume();step(10)
 elseif mode=='held' then R.SessionPause.Pause();step(40);R.SessionPause.Resume() end
 local requestsAfter=0
 holding=false
 for _,packet in ipairs(held) do
  local text=packet.text
  if foreignId then text=text:gsub(requestId:gsub('(%W)','%%%1'),'c1-unrelated') end
  P.Channel(receiver,text,source.e.UnitName('player'))
 end
 step(60)
 for i=sentBefore+1,#receiver.H.sent do
  local code=wire(receiver.H.sent[i]):match('^([^|]+)')
  if code=='WLRQ' then requestsAfter=requestsAfter+1 end
 end
 local state=R.Sync.Stats()
 return {record=R.DpsCapture.GetCharacterBest('lk','Origin',row.o),state=state,
  requestsAfter=requestsAfter,requestId=requestId,actions=#receiver.H.actions+#source.H.actions}
end

Case('control',function()
 local r=Run('control')
 assert(r.record and r.record.dps==47000,'unpaused: the correlated answer is recorded')
 assert(r.state.requestId==r.requestId and (r.state.requestUpdated or 0)>0,'unpaused: it counts for the request')
end)
Case('quick Pause and Resume',function()
 local r=Run('quick')
 assert(r.record and r.record.dps==47000,'the answer to the request sent before the pause settles after Resume')
 assert(r.state.requestId==r.requestId and (r.state.requestUpdated or 0)>0,'it counts for its own request: updated='..tostring(r.state.requestUpdated))
 assert(r.requestsAfter==0,'the old grant sends no further request: '..r.requestsAfter)
 assert(r.actions==0,'no game action')
end)
Case('paused with updates',function()
 local r=Run('held')
 assert(r.record and r.record.dps==47000,'still settles after a pause with updates')
 assert((r.state.requestUpdated or 0)>0 and r.requestsAfter==0,'counted once, nothing more sent')
end)
Case('foreign request ID after quick pause',function()
 local r=Run('quick',true)
 assert((r.state.requestUpdated or 0)==0,'an answer to another request ID is not progress for this one')
end)

assert(#failures==0,'failed cases: '..table.concat(failures,', '))
print('PASS session pause keeps sent Sync requests settleable without new sends')
