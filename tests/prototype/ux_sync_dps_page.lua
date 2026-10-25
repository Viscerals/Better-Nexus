-- UX M5 14d (MB2 / M5R-NB06 path / M5R-NB07): the click-free automatic
-- Record Loadout page of a new personal DPS best, through the real
-- production pipeline: DpsCapture new character best ->
-- CommunityBuilds.EnsureDpsBuildForEchoes -> controller SaveBuild/commit ->
-- implicit BroadcastIfPossible -> Sync.BroadcastBuildSummary ->
-- Compatibility.PrepareSummary (size) -> queue admission
-- (SyncModePolicy.Allows). Every boot is fresh: no explicit Sync Now grant and
-- no explicit Share of the page exist.
-- 14e: the mode scenarios use a supported player identity (a 12-character
-- name; game names have 2-12 letters). The harness default 'PrototypeTester'
-- has 15, which makes the page summary 251 escaped bytes, over the 247-byte
-- line budget, so it was refused "summary too large" before any mode decision.
-- Automatic (EXPECT that it is disclosed; GUARD that it happens): the page's
-- summary is admitted without any click, and it is a summary without the Echo
-- list (WLBI) that fits one line; no full record (WLRB) goes out unasked.
-- Manual and Off (both through the player's explicit choice, an EXPECT on the
-- preimage which has no choice, and through accepted legacy format-5
-- settings, a GUARD): the same pipeline hands the page to Sync, the existing
-- admission refuses it with the policy's own reason, and no summary, full
-- record or DPS record leaves the client.
-- Size boundary (GUARD): with the 15-character harness name, and with a
-- supported 12-character Death Knight (longer class and title), Automatic
-- refuses the page summary locally as "summary too large" before admission;
-- no summary or full record of that page leaves the client, no other packet
-- names the page, and it is not counted as a mode refusal.
-- 14f: the same new best is also sent as its own DPS record (DpsCapture ->
-- Sync.BroadcastDpsRecord, WLD2), a separate documented Automatic send that
-- the page refusal does not silence. Every packet since the capture is
-- printed with its code, class and identity. In Automatic (AUTO, BH, BD) any
-- WLD2 must be the captured record: its transfer identity player:time:DPS,
-- and its reassembled, decoded fields (player, time, DPS, category, owner,
-- class), with only DPS record fields (GUARD). M5 queue item 3: the Echo set
-- is established from the decoded list itself (production codec; production
-- canonical key equal to the record's fingerprint; entries equal where the
-- read record carries them; locked list equal), not from the payload's own f
-- claim. A transmission that did not reassemble or decode in the window
-- establishes nothing and is printed as such. Oversized DPS records
-- (Sync MAX_ENCODED_BYTES) are not reached by this capture and stay qualified.
-- Superseded page (GUARD, existing actors): a later better best with another
-- Echo set removes the earlier automatic page locally. Sync.BroadcastDelete
-- may first return ROOT_MUTATION_PENDING (the local tombstone is still being
-- committed); its own completion receipt then reports the local removal and
-- the wire refused with REMOTE_TOMBSTONE_ORDER_UNPROVEN, the local tombstone
-- is kept and zero removal bytes (WLRD) are sent before or after. No peer
-- recall is claimed.
-- Help (EXPECT): its share sentence is qualified and names the page; M5 queue
-- item 3: the automatic new best is a possible send decided by local
-- admission (size, checks, a full send queue; Manual/Off), and neither
-- delivery nor reception is promised. GUARD: no removal or recall on other
-- clients is claimed.
-- D2/D3: new disclosure EXPECTs replace obsolete personal-best/requester-only
-- needles. Added GUARDs characterize existing behavior: a nonwinning exact-set
-- best stays local; captured WLD2 includes locked evidence and alone lets a
-- fresh peer store and open/copy the exact page. No behavior repair is claimed.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- Boundaries: synthetic Details! combat and training-dummy target as in
-- batch_class_capture_publication; the player identity is set per boot as
-- sync_pair_support does; Sync.BroadcastBuildSummary and BroadcastDelete are
-- observed by pass-through spies that call the real functions and keep their
-- exact results (the delete spy wraps the caller's completion callback and
-- still calls it). No native or server claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local T=dofile('tests/prototype/startup_support.lua')
local printable=V.printable
local C=V.Checker('ux_sync_dps_page')

-- WoW's chat line limit and the Sync safety margin (core/Sync.lua).
local LINE_BUDGET=255-8
local SUPPORTED={name='Pagecapturer'}
local DEATH_KNIGHT={name='Deathrecords',class={'Death Knight','DEATHKNIGHT',6}}

local H,A,D,S,P
local summaries,deletes
local function Boot(configure,identity)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 NexusCommunityBuildsFrame,NexusHelpWindow,NexusSyncModeDialog=nil,nil,nil
 H=dofile('tests/prototype/harness.lua')
 if identity and identity.name then UnitName=function() return identity.name,'Ebonhold' end end
 if identity and identity.class then
  local class=identity.class
  UnitClass=function() return class[1],class[2],class[3] end
 end
 H.playerLevel=10
 NexusDB=T.Profile(0,0)
 if configure then configure(NexusDB) end
 for i=1,3 do H.AddEcho(300000+i,'Synthetic page Echo '..i,2,4,300000+i) end
 T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
 T.Until(H,function() return Nexus.StartupStatus().state=='ready' end)
 A,D,S,P=Nexus.GameAdapter,Nexus.DpsCapture,Nexus.Sync,Nexus.SyncModePolicy
 summaries,deletes={},{}
 local realSummary=S.BroadcastBuildSummary
 S.BroadcastBuildSummary=function(record,options)
  local ok,queued,why,status=pcall(realSummary,record,options)
  summaries[#summaries+1]={id=type(record)=='table' and record.id,autoDps=type(record)=='table' and record.autoDps,
   title=type(record)=='table' and record.title,explicit=options~=nil,ok=ok,queued=queued,why=why}
  if not ok then error(queued,0) end
  return queued,why,status
 end
 local realDelete=S.BroadcastDelete
 S.BroadcastDelete=function(build,onLocalComplete,...)
  local entry={id=type(build)=='table' and build.id,callbacks=0}
  deletes[#deletes+1]=entry
  local observed=onLocalComplete
  if type(onLocalComplete)=='function' then
   observed=function(receipt,...)
    entry.callbacks=entry.callbacks+1
    entry.final=receipt
    return onLocalComplete(receipt,...)
   end
  end
  local results={pcall(realDelete,build,observed,...)}
  entry.ok,entry.queued,entry.why=results[1],results[2],results[3]
  local receipt=results[5]
  entry.firstPending=type(receipt)=='table' and receipt.localPending==true
  -- A direct completion returns its receipt at once; a pending one delivers it
  -- later through the completion callback of its own catalog ticket.
  if type(receipt)=='table' and not entry.firstPending then entry.final=receipt end
  if not results[1] then error(results[2],0) end
  return unpack(results,2)
 end
 return H
end
-- Owned and active Echo set for the next capture.
local function UseEchoes(id)
 H.granted={['Synthetic page Echo '..(id-300000)]={{spellId=id,quality=2}}}
 H.locked={}
 H.perks.serverBuildSlots={[1]={name='Synthetic slot',verified=true,echoes={{spellId=id,quality=2,stacks=1,locked=false}}}}
 H.perks.serverActiveSlot=1
 H.Notify();A.Poll()
end
local combat={total=0}
function combat:GetActor() return {total=self.total,Tempo=function() return 30 end} end
function combat:GetCombatTime() return 30 end
local function Capture(total)
 local realName=UnitName
 UnitName=function(unit) if unit=='target' then return 'Training Dummy' end;return realName(unit) end
 UnitExists=function(unit) return unit=='target' end
 Details={GetCurrentCombat=function() return combat end};DETAILS_ATTRIBUTE_DAMAGE=1
 combat.total=total
 D.OnCombatStart()
 for _=1,7 do H.Advance(5,.05);D.OnUpdate(5) end
 local ok,err=pcall(D.OnCombatEnd)
 UnitName=realName
 return ok,err
end
local function AutoSummary(since)
 for i=since+1,#summaries do if summaries[i].autoDps==true and not summaries[i].explicit then return summaries[i] end end
 return nil
end
local function Plain(text) return (tostring(text or ''):gsub('||','|'):gsub('^P%d+:','')) end
local function Packets(since,code)
 local list={}
 for i=since+1,#H.sent do
  local text=Plain(H.sent[i].text)
  if text:find('^'..code..'|') then list[#list+1]=text end
 end
 return list
end
local function Codes(since,code) return #Packets(since,code) end
-- Escaped wire length as the Sync budget counts it: each '|' is doubled.
local function Escaped(text) local _,pipes=text:gsub('|','');return #text+pipes end
local function Until(limit,fn) for _=1,limit do if fn() then return true end;H.Advance(.05,.05) end;return fn() end

-- 14f: packet identity. A new best makes two independent sends: the page's
-- summary (Sync.BroadcastBuildSummary, WLBI) and the captured DPS record
-- itself (DpsCapture new-best branch -> Sync.BroadcastDpsRecord, WLD2:
-- "WLD2|sender|player:ts:dps|i/total|chunk[|requester|requestId|bucket]",
-- the chunks joining to Base64(JSON) of the record's fields). Each packet
-- is classified by code and exact identity; nothing is muted or stubbed.
local function Fields(text)
 local f={}
 for field in (Plain(text)..'|'):gmatch('([^|]*)|') do f[#f+1]=field end
 return f
end
local function Decode(data)
 local codec=Nexus.Codec
 local ok,payload=pcall(function() return codec.JSONDecode(codec.Base64Decode(data)) end)
 return ok and type(payload)=='table' and payload or nil
end
-- The DPS record's own fields (Sync.BroadcastDpsRecord payload).
local DPS_FIELDS={v=true,h=true,f=true,e=true,c=true,d=true,u=true,t=true,p=true,l=true,k=true,o=true,r=true,b=true,lk=true,x=true}
local function RecordTransfer(record)
 if type(record)~='table' then return nil end
 return tostring(record.player)..':'..tostring(tonumber(record.ts))..':'..tostring(math.floor(tonumber(record.dps) or 0))
end
local function Traffic(since,page,record)
 local out={list={},counts={},transfers={}}
 local transferId=RecordTransfer(record)
 for i=since+1,#H.sent do
  local f=Fields(H.sent[i].text)
  local code,class,identity=f[1],nil,nil
  if code=='WLBI' then
   local payload=Decode(f[3] or '')
   class=payload and payload.id==page.id and 'page-WLBI' or 'other-WLBI'
   identity='sender='..tostring(f[2])..' id='..tostring(payload and payload.id)
  elseif code=='WLRB' then
   class=f[3]==page.id and 'page-WLRB' or 'other-WLRB'
   identity='build='..tostring(f[3])..' chunk='..tostring(f[5])
  elseif code=='WLD2' then
   class=transferId~=nil and f[3]==transferId and 'record-WLD2' or 'other-WLD2'
   identity='sender='..tostring(f[2])..' transfer='..tostring(f[3])..' chunk='..tostring(f[4])..(#f>5 and ' with request context' or '')
   -- Chunks per transmission: a chunk index seen again starts another one,
   -- so a resend is never mixed into an earlier transmission.
   local key=tostring(f[3])
   local transmissions=out.transfers[key] or {}
   out.transfers[key]=transmissions
   local index,total=tostring(f[4] or ''):match('^(%d+)/(%d+)$')
   if index then
    index=tonumber(index)
    local t=transmissions[#transmissions]
    if not t or t.chunks[index]~=nil then t={chunks={}};transmissions[#transmissions+1]=t end
    t.chunks[index]=f[5] or '';t.total=tonumber(total)
   end
  else
   class='other-'..tostring(code)
   for j=2,#f do if f[j]==page.id then class='page-ref-'..tostring(code) end end
   identity=table.concat({f[2] or '',f[3] or '',f[4] or ''},' '):sub(1,96)
  end
  out.list[#out.list+1]={index=i,code=code,class=class,identity=identity}
  out.counts[class]=(out.counts[class] or 0)+1
 end
 return out,transferId
end
local function Assemble(t)
 if type(t)~='table' or not t.total then return nil,'no chunk' end
 local parts={}
 for i=1,t.total do
  if not t.chunks[i] then return nil,'chunk '..i..' of '..t.total..' not sent' end
  parts[i]=t.chunks[i]
 end
 local payload=Decode(table.concat(parts))
 if not payload then return nil,'not decodable' end
 return payload
end
-- Every complete transmission of one transfer, decoded; and why the last
-- incomplete one (if any) is not complete.
local function Complete(transmissions)
 local payloads,why={},nil
 for _,t in ipairs(transmissions or {}) do
  local payload,reason=Assemble(t)
  if payload then payloads[#payloads+1]=payload else why=reason end
 end
 return payloads,why
end
-- One Echo list in a comparable form: each entry's id, copies and locked
-- mark, sorted. Used for the decoded payload and the captured record alike.
local function EchoList(list)
 local out={}
 for _,e in ipairs(type(list)=='table' and list or {}) do
  local entry=type(e)=='table' and e or {}
  out[#out+1]=tostring(tonumber(entry.spellId or entry.id))..'x'..tostring(tonumber(entry.count or entry.stacks) or 1)
   ..(entry.locked and 'L' or '')
 end
 table.sort(out)
 return table.concat(out,',')
end
-- The decoded record is the captured best by its production identity. The
-- Echo set is established from the decoded payload itself, not from its f
-- field (the sender copies f from the record, so f is only its claim): the
-- ordinary list e, decoded by the production codec, must give production's
-- own canonical key (DpsCapture.GetEchoKey: sorted spellIdxcount, injective)
-- equal to the record's fingerprint, and equal the record's Echoes entry by
-- entry where the read record carries them; the locked list lk must equal the
-- record's locked Echoes.
local function SameRecord(payload,record,transferId)
 if type(payload)~='table' or type(record)~='table' then return false,'missing' end
 for key in pairs(payload) do if not DPS_FIELDS[key] then return false,'field '..tostring(key)..' is not a DPS record field' end end
 if payload.p~=record.player or payload.c~='dummy' or payload.f~=record.fingerprint
  or tonumber(payload.t)~=tonumber(record.ts) or tonumber(payload.d)~=math.floor(tonumber(record.dps) or -1) then
  return false,'player/time/DPS/category/claimed fingerprint differ'
 end
 local okKey,decodedKey=pcall(D.GetEchoKey,payload.e)
 if not okKey or decodedKey==nil or decodedKey~=record.fingerprint then
  return false,'the decoded Echo list gives key '..tostring(okKey and decodedKey or 'error')..', not the record\'s '..tostring(record.fingerprint)
 end
 if type(record.echoes)=='table' and EchoList(payload.e)~=EchoList(record.echoes) then
  return false,'the decoded Echo list differs from the record\'s entries'
 end
 if EchoList(payload.lk)~=EchoList(record.lockedEchoes) then
  return false,'the decoded locked Echo list differs from the record\'s'
 end
 if record.ownerKey~=nil and payload.o~=record.ownerKey then return false,'owner differs' end
 if record.class~=nil and payload.k~=record.class then return false,'class differs' end
 if tostring(payload.p)..':'..tostring(payload.t)..':'..tostring(payload.d)~=transferId then return false,'transfer id differs' end
 return true
end
local function PageRefs(traffic)
 local n=0
 for class,count in pairs(traffic.counts) do if class:find('^page%-ref%-') then n=n+count end end
 return n
end
local function Report(tag,traffic)
 for _,p in ipairs(traffic.list) do
  print('OBSERVED',tag,'packet',p.index,printable(p.code),p.class,printable(p.identity))
 end
 local summary={}
 for class,n in pairs(traffic.counts) do summary[#summary+1]=class..'='..n end
 table.sort(summary)
 print('OBSERVED',tag,'packets since the capture',#traffic.list,table.concat(summary,' '))
end
-- Any WLD2 in the window must be the captured record: its transfer identity,
-- and once reassembled its decoded fields. Silence is also acceptable.
local function RecordGuards(tag,traffic,transferId,record,page)
 local other=traffic.counts['other-WLD2'] or 0
 C.guard(other==0,tag..': every DPS record (WLD2) sent is the captured new best, by its transfer identity',other)
 local sent=traffic.counts['record-WLD2'] or 0
 if sent==0 then
  print('OBSERVED',tag,'no WLD2 of the captured record in this window')
  return
 end
 local transmissions=traffic.transfers[tostring(transferId)] or {}
 local payloads,why=Complete(transmissions)
 local same,detail=#payloads>0,why or 'no complete transmission'
 for _,payload in ipairs(payloads) do
  local ok,reason=SameRecord(payload,record,transferId)
  print('OBSERVED',tag,'DPS record transfer='..printable(transferId),'b='..printable(payload.b),
   'b is the page='..printable(payload.b==page.id),'echoes='..printable(type(payload.e)=='table' and #payload.e or nil),
   'same record='..printable(ok),printable(reason))
  if not ok then same,detail=false,reason end
 end
 -- Transmissions that did not reassemble (a chunk not sent in this window, or
 -- data the production codec cannot decode) establish nothing either way.
 print('OBSERVED',tag,'DPS record chunks='..sent,'transmissions='..#transmissions,'complete='..#payloads,
  'not established='..(#transmissions-#payloads)..(why and (' ('..why..')') or ''),
  'record echoes read='..printable(type(record)=='table' and type(record.echoes)=='table'))
 C.guard(same,tag..': it reassembles to that record (player, time, DPS, category, owner, class) with only DPS record fields,'
  ..' and its decoded Echo list is the record\'s exact Echo set (production key and entries)',printable(detail))
end

local function Run(tag,mode,configure,viaChoice,expectChoice,identity,boundary)
 Boot(configure,identity)
 C.setup(Nexus.StartupStatus().state=='ready',tag..': fixture: start-up ready')
 local name=UnitName('player')
 print('OBSERVED',tag,'player='..printable(name),'length='..#tostring(name),'class='..printable(select(2,UnitClass('player'))))
 if viaChoice then
  local ok,result=false,'no-policy-route'
  if type(P.ApplyChoice)=='function' then ok,result=P.ApplyChoice(mode) end
  local check=expectChoice and C.expect or C.setup
  check(ok==true and P.Mode()==mode,tag..': the player\'s explicit choice '..mode..' is saved and honoured',printable(result))
  if P.Mode()~=mode then return end
 end
 C.setup(P.Mode()==mode,tag..': fixture: the effective mode is '..mode,P.Mode())
 C.setup(P.ActiveManualGrant()==nil,tag..': fixture: fresh, with no explicit Sync Now grant')
 UseEchoes(300001)
 local sent0,refused0=#H.sent,(S.Stats().modeRefused or 0)
 local ok,err=Capture(90000)
 C.setup(ok,tag..': fixture: the real combat end ran',err)
 local row=D.GetCurrentPersonalBest('dummy')
 C.setup(type(row)=='table' and row.dps==3000,tag..': fixture: the capture committed a new personal best',row and row.dps)
 Until(2000,function() return AutoSummary(0)~=nil end)
 local page=AutoSummary(0)
 C.setup(page~=nil and tostring(page.title or ''):find('Record Loadout',1,true)~=nil,
  tag..': fixture: the pipeline created the automatic Record Loadout page and handed it to Sync without a click',page and page.title)
 if not page then return end
 C.guard(S.GetShareStatus(page.id)==nil or S.GetShareStatus(page.id).id~=page.id,tag..': no explicit Share of that page exists')
 print('OBSERVED',tag,'page='..printable(page.id),'title='..printable(page.title),'admission queued='..printable(page.queued),'why='..printable(page.why))
 if mode=='automatic' and not boundary then
  Until(1200,function() return Codes(sent0,'WLBI')>=1 end)
 else
  for _=1,200 do H.Advance(.05,.05) end
 end
 -- In Automatic, the captured record's WLD2 transfer is identified once it
 -- has fully left (bounded ordinary progression; nothing replayed).
 if mode=='automatic' then
  Until(600,function()
   local t,id=Traffic(sent0,page,row)
   return #(Complete(t.transfers[tostring(id)]))>0
  end)
 end
 local traffic,transferId=Traffic(sent0,page,row)
 Report(tag,traffic)
 if boundary then
  C.guard(page.queued~=true and page.why=='summary too large',
   tag..': the page summary over one line is refused locally before admission',printable(page.why))
  C.guard((traffic.counts['page-WLBI'] or 0)==0 and (traffic.counts['page-WLRB'] or 0)==0,
   tag..': no summary or full record of the generated page leaves the client',
   (traffic.counts['page-WLBI'] or 0)..'/'..(traffic.counts['page-WLRB'] or 0))
  C.guard(PageRefs(traffic)==0,tag..': no other packet names the generated page',PageRefs(traffic))
  C.guard((traffic.counts['record-WLD2'] or 0)>0,tag..': the eligible DPS record leaves independently of page summary admission')
  RecordGuards(tag,traffic,transferId,row,page)
  C.guard((S.Stats().modeRefused or 0)==refused0,tag..': it is a size refusal, not a mode refusal',(S.Stats().modeRefused or 0)-refused0)
 elseif mode=='automatic' then
  C.guard(page.queued==true,tag..': Automatic admits the page summary with no click',printable(page.why))
  C.guard(Codes(sent0,'WLBI')>=1,tag..': and it leaves as a build summary (WLBI)',Codes(sent0,'WLBI'))
  local wire=Packets(sent0,'WLBI')[1]
  if wire then
   local fields={}
   for field in (wire..'|'):gmatch('([^|]*)|') do fields[#fields+1]=field end
   local codec=Nexus.Codec
   local okDecode,payload=pcall(function() return codec.JSONDecode(codec.Base64Decode(fields[3])) end)
   print('OBSERVED',tag,'WLBI escaped bytes='..Escaped(wire),'budget='..LINE_BUDGET)
   C.guard(okDecode and type(payload)=='table' and payload.id==page.id and payload.x==1 and payload.a==name,
    tag..': the summary on the wire is this page\'s, sent by this player',okDecode and type(payload)=='table' and printable(payload.id) or printable(payload))
   C.guard(Escaped(wire)<=LINE_BUDGET,tag..': it fits one line within the Sync budget',Escaped(wire))
  end
  C.guard(Codes(sent0,'WLRB')==0,tag..': its full record with the Echo list (WLRB) is not sent unasked',Codes(sent0,'WLRB'))
  C.guard((traffic.counts['record-WLD2'] or 0)>0,tag..': the eligible DPS record leaves independently of page summary admission')
  RecordGuards(tag,traffic,transferId,row,page)
 else
  C.guard(page.queued==false and P.IsModeReason(page.why),tag..': '..mode..' refuses the page summary at admission with the policy\'s reason',
   printable(page.why))
  C.guard(Codes(sent0,'WLBI')==0 and Codes(sent0,'WLRB')==0 and Codes(sent0,'WLD2')==0,
   tag..': no summary, full record or DPS record leaves the client',#H.sent-sent0)
  C.guard((S.Stats().modeRefused or 0)>refused0,tag..': the refusal is counted as a mode refusal',(S.Stats().modeRefused or 0)-refused0)
 end
 -- A better best with another Echo set supersedes the page: local removal only.
 UseEchoes(300002)
 local sent1=#H.sent
 ok,err=Capture(120000)
 C.setup(ok,tag..': fixture: the second combat end ran',err)
 Until(2000,function() return #deletes>0 end)
 local removal=deletes[1]
 C.setup(removal~=nil and removal.id==page.id,tag..': fixture: the superseded page was removed through DeleteBuild',removal and removal.id)
 if removal then
  print('OBSERVED',tag,'delete first return='..printable(removal.why),'pending='..printable(removal.firstPending))
  C.guard(removal.ok==true and removal.queued==false
   and (removal.why=='REMOTE_TOMBSTONE_ORDER_UNPROVEN' or removal.why=='ROOT_MUTATION_PENDING' and removal.firstPending),
   tag..': BroadcastDelete admits nothing to the wire on its first return (refused, or the local tombstone still committing)',
   printable(removal.why))
  C.guard(Codes(sent1,'WLRD')==0,tag..': zero removal bytes (WLRD) before completion',Codes(sent1,'WLRD'))
  -- Ordinary bounded progression completes the owned ticket; nothing is replayed.
  Until(400,function() return removal.final~=nil end)
  local final=removal.final
  print('OBSERVED',tag,'delete completion',type(final)=='table' and printable(final.queueReason) or 'none','callbacks='..removal.callbacks)
  C.guard(type(final)=='table' and final.localPending==false and final.localRemoved==true and final.queueAdmitted==false
   and final.queueReason=='REMOTE_TOMBSTONE_ORDER_UNPROVEN',
   tag..': its completion receipt reports the local removal and the wire refused with REMOTE_TOMBSTONE_ORDER_UNPROVEN',
   type(final)=='table' and printable(final.queueReason) or 'no receipt')
  C.guard(removal.callbacks==(removal.firstPending and 1 or 0),
   tag..': a pending removal completes exactly once through its own ticket',removal.callbacks)
  local status=S.GetDeleteStatus(page.id)
  C.guard(type(status)=='table' and status.kind=='delete' and status.id==page.id and status.outcome=='rejected'
   and status.reason=='REMOTE_TOMBSTONE_ORDER_UNPROVEN' and status.queueAdmitted==false and status.sent==false,
   tag..': the delete status ends rejected with that reason, never queued or sent',type(status)=='table' and printable(status.outcome))
  local catalog=Nexus.BuildCatalog
  Until(400,function() return catalog.Get(page.id)==nil end)
  local tomb=catalog.TombstoneState(page.id)
  C.guard(catalog.Get(page.id)==nil and type(tomb)=='table' and tomb.state~='NONE',
   tag..': the page is removed locally and its tombstone is kept',type(tomb)=='table' and tomb.state)
  for _=1,100 do H.Advance(.05,.05) end
  C.guard(Codes(sent1,'WLRD')==0,tag..': zero removal bytes (WLRD) are sent',Codes(sent1,'WLRD'))
 end
 C.guard(#H.actions==0,tag..': no game action',#H.actions)
end

local function Legacy(mode) return function(db) db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode=mode end end
C.scenario('AUTO Automatic (current profile)',function() Run('AUTO','automatic',nil,false,nil,SUPPORTED) end)
C.scenario('MC Manual chosen by the player',function() Run('MC','manual',nil,true,true,SUPPORTED) end)
C.scenario('OC Off chosen by the player',function() Run('OC','off',nil,true,true,SUPPORTED) end)
C.scenario('ML Manual from accepted format-5 settings',function() Run('ML','manual',Legacy('manual'),false,nil,SUPPORTED) end)
C.scenario('OL Off from accepted format-5 settings',function() Run('OL','off',Legacy('off'),false,nil,SUPPORTED) end)
C.scenario('BH size boundary: the 15-character harness name',function() Run('BH','automatic',nil,false,nil,nil,true) end)
C.scenario('BD size boundary: a supported 12-character Death Knight',function() Run('BD','automatic',nil,false,nil,DEATH_KNIGHT,true) end)

C.scenario('D23 unsolicited locked record, nonwinning set and WLD2-only receiver',function()
 Boot(nil,SUPPORTED)
 UseEchoes(300001)
 H.locked={{spellId=300003,quality=2,stacks=1}}
 H.Notify();A.Poll()
 local sent0=#H.sent
 local ok,err=Capture(120000)
 C.setup(ok,'D23: qualifying capture completed',err)
 local row=D.GetCurrentPersonalBest('dummy')
 C.setup(type(row)=='table' and row.dps==4000 and #row.lockedEchoes==1,
  'D23: actual capture has ordinary and nonempty locked evidence')
 Until(2000,function() return AutoSummary(0)~=nil end)
 local page=AutoSummary(0)
 C.setup(page~=nil,'D23: actual capture created its page')
 if not page or not row then return end
 Until(1200,function()
  local t,id=Traffic(sent0,page,row)
  return #(Complete(t.transfers[tostring(id)]))>0
 end)
 local traffic,transferId=Traffic(sent0,page,row)
 RecordGuards('D23',traffic,transferId,row,page)
 local chunks={}
 for i=sent0+1,#H.sent do
  local f=Fields(H.sent[i].text)
  if f[1]=='WLD2' and f[3]==transferId then
   C.guard(#f==5,'D23: captured record has no requester/request context')
   chunks[#chunks+1]=H.sent[i].text
  end
 end
 C.setup(#chunks>0,'D23: retained real WLD2 chunks for a fresh peer')
 local payloads=Complete(traffic.transfers[tostring(transferId)])
 C.guard(#payloads>0 and #payloads[1].e==1 and #payloads[1].lk==1,
  'D23: decoded real record carries ordinary and nonempty locked Echoes')

 -- A weaker best for a different exact set is saved locally, but never
 -- handed to automatic egress or automatic page creation.
 local calls={}
 local real=S.BroadcastDpsRecord
 S.BroadcastDpsRecord=function(record,...) calls[#calls+1]=record;return real(record,...) end
 UseEchoes(300002)
 local mark=#summaries
 ok,err=Capture(90000)
 local weaker=D.GetCurrentPersonalBest('dummy')
 local winner=D.GetCharacterBest('dummy')
 C.setup(ok and weaker and weaker.dps==3000 and weaker.fingerprint~=row.fingerprint,
  'D23: another exact set committed its own weaker personal best',err)
 C.guard(winner and winner.dps==4000 and winner.fingerprint==row.fingerprint,
  'D23: the encounter character best stays the stronger set')
 C.guard(#calls==0 and AutoSummary(mark)==nil,
  'D23: a nonwinning personal best starts neither automatic DPS transfer nor page summary',#calls)
 S.BroadcastDpsRecord=real

 -- Only captured WLD2 crosses into a fresh runtime. No WLBI, WLRB or
 -- direct EnsureDpsBuildForEchoes call is injected into the receiver.
 local expectedOrdinary,expectedLocked=EchoList(row.echoes),EchoList(row.lockedEchoes)
 local sourceName=Fields(chunks[1])[2]
 Boot(nil,{name='Pagereceiver'})
 NexusEditorFrame=nil
 C.setup(Nexus.BuildCatalog.Get(page.id)==nil,'D23: receiver begins with no sender page')
 for _,text in ipairs(chunks) do
  H.Fire('CHAT_MSG_CHANNEL',text,sourceName,nil,'1. '..S.ChannelName(),nil,nil,nil,nil,S.ChannelName())
 end
 Until(2400,function()
  local r=D.GetCharacterBest('dummy',sourceName)
  return r and r.buildId and Nexus.BuildCatalog.Get(r.buildId)~=nil
 end)
 local received=D.GetCharacterBest('dummy',sourceName)
 local stored=received and Nexus.BuildCatalog.Get(received.buildId)
 C.guard(received and received.dps==4000 and stored and EchoList(stored.echoes)==expectedOrdinary
  and EchoList(received.lockedEchoes)==expectedLocked,
  'D23: WLD2 alone stores the exact page and locked DPS evidence')
 if stored then
  Nexus.CommunityBuilds.ShowBuild(stored.id)
  local f=NexusCommunityBuildsFrame
  Until(2000,function() return f and f._detailPanel and f._detailPanel._nexusShownId==stored.id end)
  local detail=f and f._detailPanel
  C.guard(f and f:IsShown() and detail and detail._nexusShownId==stored.id,
   'D23: receiver opens the stored Record Loadout page')
  C.setup(detail and detail.lockBtn and V.Plain(detail.lockBtn:GetText())=='Copy into Editor',
   'D23: receiver exposes the real Copy into Editor action')
  if detail and detail.lockBtn then detail.lockBtn:Click() end
  local draft=Nexus.WishlistEditor.DebugDraftState()
  C.guard(NexusEditorFrame and NexusEditorFrame:IsShown()
   and draft.pending==1 and draft.pendingLock==1,
   'D23: receiver can copy ordinary and locked roles into Editor',
   tostring(draft.pending)..'/'..tostring(draft.pendingLock))
 end
 C.guard(#H.actions==0,'D23: receiver performs no game action',#H.actions)
end)

C.scenario('HELP the share sentence is qualified',function()
 Boot()
 Nexus.Help.Show('sharing')
 local help=V.Plain(NexusHelpWindow and NexusHelpWindow.body:GetText() or ''):gsub('%s+',' ')
 C.expect(help:find('Sharing a build always needs your click',1,true)==nil,'HELP: the false categorical claim is gone')
 C.expect(help:find('Your own Share actions need your click',1,true)~=nil
  and help:find('an eligible new character best for Training Dummy or Lich King may send without a click',1,true)~=nil
  and help:find('Record Loadout',1,true)~=nil,'HELP: it says own Shares need a click and Automatic shares a DPS best page without one')
 C.expect(help:find('removes the old page on this client only',1,true)~=nil,'HELP: the superseded page removal is local only')
 -- M5 queue item 3: a possible send, then the local admission that decides
 -- it, and no promise of delivery or reception (the categorical form is gone).
 C.expect(help:find('also shared without a click, as an automatic',1,true)==nil
  and help:find('ordinary and any locked Echoes and player info',1,true)~=nil
  and help:find('Each of these leaves only if this client admits it',1,true)~=nil
  and help:find('Refusing the summary does not refuse the separate DPS record',1,true)~=nil,
  'HELP: the automatic new-best share is a possible send that local admission decides, in both places')
 C.expect(help:find('An oversized summary is refused separately; it does not stop an otherwise admitted DPS record',1,true)~=nil
  and help:find('a record or summary that is too large, fails its checks or finds the send queue full stays here',1,true)~=nil,
  'HELP: the local refusals (too large, failed checks, a full send queue) are stated')
 C.expect(help:find('Sending is not delivery',1,true)~=nil and help:find('What leaves may still reach no one',1,true)~=nil,
  'HELP: neither delivery nor reception of the automatic share is promised')
 C.guard(help:find('It sends no removal, so players who already received the page keep it',1,true)~=nil
  and help:find('Changing the mode cannot recall anything already sent',1,true)~=nil,
  'HELP: no removal or recall on other clients is claimed')
end)

C.finish('(the automatic Record Loadout page is disclosed; Manual/Off refuse it at admission; oversized summaries are refused locally; superseded pages are removed locally only)')
