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
-- D23 quality (GUARD; catalog metadata is SETUP): each representation has its
-- own literal pin, compared exactly (an absent quality never matches 0): the
-- raw capture, its WLD2 and the received DPS record state no quality; the
-- stored page states the canonical 0; the copied draft states ordinary 2
-- (catalog enrichment) and locked 0. D23Q is an independent public typed
-- known-quality control. The earlier quality-2 draft expectation for both
-- roles was an unsupported hypothesis; its archived failure stays as it is and
-- is not product-behavior red evidence. No owned rarity or repair is claimed.
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
-- D23: one Echo list as exact rows in its own representation. The role is
-- the container's (the ordinary or the locked list that was read); an entry's
-- own marker (locked, sourceRole, lockIntent) is optional and may only agree
-- with it. ID and copies are read through the aliases and the one-copy
-- default of the DPS wire (DpsCapture WireEchoValue); aliases must agree.
-- Quality is kept only where the entry states it (as a number), so a raw
-- capture or wire list is compared in its own form: no quality is supplied to
-- it and an absent quality stays nil, never 0. A missing or non-dense list,
-- or a malformed entry, ID, count, quality or marker, is an error and never an
-- empty list.
local function D23Whole(v,least) return v~=nil and v>=least and v<math.huge and v==math.floor(v) end
local function D23Rows(list,role)
 if type(list)~='table' then return nil,role..' list is missing ('..type(list)..')' end
 local n=0
 for _ in pairs(list) do n=n+1 end
 if n~=#list then return nil,role..' list is not a dense array' end
 local rows={}
 for i=1,n do
  local e=list[i]
  if type(e)~='table' then return nil,role..' entry '..i..' is not a table' end
  local id,count=e.spellId,nil
  if id==nil then id=e.id elseif e.id~=nil and tonumber(e.id)~=tonumber(id) then
   return nil,role..' entry '..i..' has disagreeing IDs'
  end
  for _,key in ipairs({'count','stacks','stack'}) do
   if e[key]~=nil then
    if count~=nil and tonumber(e[key])~=tonumber(count) then return nil,role..' entry '..i..' has disagreeing copies' end
    count=e[key]
   end
  end
  id,count=tonumber(id),tonumber(count==nil and 1 or count)
  local quality,locked=tonumber(e.quality),e.locked
  if not D23Whole(id,1) or not D23Whole(count,1) or (e.quality~=nil and (type(e.quality)~='number' or not D23Whole(quality,0)))
   or (locked~=nil and locked~=true and locked~=false and locked~=0 and locked~=1) then
   return nil,role..' entry '..i..' has an invalid ID, count, quality or locked marker'
  end
  if role=='ordinary' and (locked==true or locked==1 or e.lockIntent or (e.sourceRole~=nil and e.sourceRole~='ordinary'))
   or role=='locked' and (locked==false or locked==0 or (e.sourceRole~=nil and e.sourceRole~='locked')) then
   return nil,role..' entry '..i..' is marked with the other role'
  end
  rows[i]={id=id,count=count,quality=quality,role=role}
 end
 table.sort(rows,function(a,b)
  if a.id~=b.id then return a.id<b.id end
  if a.count~=b.count then return a.count<b.count end
  return (a.quality or -1)<(b.quality or -1)
 end)
 return rows
end
-- D23: the ordinary rows, then the locked rows, of one representation.
local function D23Exact(ordinary,locked)
 local rows,why=D23Rows(ordinary,'ordinary')
 if not rows then return nil,why end
 local lockedRows;lockedRows,why=D23Rows(locked,'locked')
 if not lockedRows then return nil,why end
 for _,r in ipairs(lockedRows) do rows[#rows+1]=r end
 return rows
end
local function D23Text(rows)
 local out={}
 for i,r in ipairs(type(rows)=='table' and rows or {}) do out[i]=r.id..'x'..r.count..'q'..tostring(r.quality or '-')..':'..r.role end
 return table.concat(out,',')
end
-- D23: does an actual ordinary and locked list hold exactly the expected rows,
-- ID, copies, role and quality each exactly? An expected row states either no
-- quality (nil, ABSENT) or one integer, and nil never matches an integer in
-- either direction. Returns the verdict and a printable detail.
local function D23Match(ordinary,locked,expected)
 local actual,why=D23Exact(ordinary,locked)
 if not actual then return false,why end
 if type(expected)~='table' then return false,'no expected rows' end
 local same=#actual==#expected
 for i=1,same and #expected or 0 do
  local a,b=actual[i],expected[i]
  if a.id~=b.id or a.count~=b.count or a.role~=b.role or a.quality~=b.quality then same=false end
 end
 return same,D23Text(actual)..(same and '' or ' is not '..D23Text(expected))
end
-- D23 literal pins, one per representation, written out here and never
-- derived from a production normalizer or from actual rows. IDs, copies and
-- roles are the fixture's (UseEchoes(300001), H.locked 300003 x1). Quality
-- follows each representation's source/schema policy, not owned rarity:
-- RAW: DpsCapture snapshots (NormalizeEchoes; Adapter.LockedOwned bySpell)
--  carry IDs and counts only; the WLD2 wire and the received DPS record keep
--  that form, so quality is ABSENT (nil), not 0.
-- PAGE: the stored page is canonical (LoadoutEvidence.Normalize), where an
--  unstated quality is the canonical default 0: not a documented unknown
--  sentinel and not proof of Common.
-- DRAFT: the public NormalizeCandidateEvidence policy: an ordinary row takes
--  the catalog quality first (here catalog metadata 2); a locked row takes a
--  stated quality first, then the catalog's, then 0 (here 0, the value the
--  stored page states; which list Copy read is not asserted).
local function D23Row(id,count,quality,role) return {id=id,count=count,quality=quality,role=role} end
local D23_RAW={D23Row(300001,1,nil,'ordinary'),D23Row(300003,1,nil,'locked')}
local D23_PAGE={D23Row(300001,1,0,'ordinary'),D23Row(300003,1,0,'locked')}
local D23_DRAFT={D23Row(300001,1,2,'ordinary'),D23Row(300003,1,0,'locked')}
-- D23: the controls of one pin. Its own known-good rows {ordinary, locked}
-- must be accepted and every control {label, ordinary, locked} refused; a
-- raise counts as not holding.
local function D23Controls(tag,pin,good,controls)
 local ok,accepted,detail=pcall(D23Match,good[1],good[2],pin)
 C.guard(ok and accepted==true,'D23: the '..tag..' pin accepts its own known-good rows',printable(detail))
 for _,c in ipairs(controls) do
  local okControl,acceptedControl,why=pcall(D23Match,c[2],c[3],pin)
  C.guard(okControl and acceptedControl==false,'D23: the '..tag..' pin rejects '..c[1],printable(why))
 end
end
-- D23: a verified owner read is the expected one only when both are present
-- and equal; nil never passes, not even against a nil expectation.
local function D23Owner(actual,expected) return expected~=nil and actual~=nil and actual==expected end
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
-- D23 wire fields. Sync.BroadcastDpsRecord sends r=record.realm,
-- l=tonumber(record.level) and u=tonumber(record.duration) (the codec writes
-- each number with tostring), and b only through VerifiedDpsBuildId: the
-- build ID when the catalog row is the ordinary page of the record's verified
-- owner with the record's fingerprint, otherwise nothing. The expectations are
-- the captured row and the page ID the test itself established; pageId nil
-- means the producer had no verified link, so b must be absent. An absent,
-- mistyped or changed value is refused with its reason; nothing here raises.
local function RecordWireFields(payload,record,pageId)
 if type(payload)~='table' or type(record)~='table' then return false,'missing decoded record or captured row' end
 local function Wire(value)
  local n=tonumber(value)
  if n==nil or n~=n or n==math.huge or n==-math.huge then return nil end
  return tonumber(tostring(n))
 end
 local realm,level,duration=record.realm,Wire(record.level),Wire(record.duration)
 if type(realm)~='string' or realm=='' or level==nil or duration==nil then
  return false,'the captured row has no realm, level or duration to compare'
 end
 if type(payload.r)~='string' or payload.r~=realm then return false,'r is absent or not the captured realm' end
 if type(payload.l)~='number' or Wire(payload.l)~=level then return false,'l is absent or not the captured level' end
 if type(payload.u)~='number' or Wire(payload.u)~=duration then return false,'u is absent or not the captured duration' end
 if pageId==nil then
  if payload.b~=nil then return false,'b is present although the producer had no verified page link' end
 elseif type(pageId)~='string' or pageId=='' then
  return false,'no established verified page ID to compare'
 elseif payload.b~=pageId then
  return false,'b is absent or not the verified page'
 end
 return true
end
-- Controls of that oracle on copies of one real decoded record (the decoded
-- record itself is not changed): unchanged it is accepted; one missing,
-- changed or mistyped r, l or u, a missing, wrong or mistyped b, or any b
-- where the producer had no verified link, is refused. Returns the controls
-- that did not hold; a raise counts as not holding.
local function RecordWireControls(payload,record,pageId,decoy)
 if type(payload)~='table' then return {'no decoded record to control'} end
 local failed={}
 local function Control(label,key,value,accept)
  local copy={}
  for k,v in pairs(payload) do copy[k]=v end
  if key then copy[key]=value end
  local ok,accepted,why=pcall(RecordWireFields,copy,record,pageId)
  if not ok then failed[#failed+1]=label..' raised'
  elseif (accepted==true)~=accept then failed[#failed+1]=label..(accept and ' refused ('..printable(why)..')' or ' accepted') end
 end
 local other=type(decoy)=='string' and decoy~=pageId and decoy or tostring(pageId)..'-other'
 Control('unchanged',nil,nil,true)
 Control('missing r','r',nil,false);Control('changed r','r',tostring(payload.r)..'-other',false);Control('mistyped r','r',{},false)
 Control('missing l','l',nil,false);Control('changed l','l',(tonumber(payload.l) or 0)+1,false);Control('mistyped l','l',tostring(payload.l),false)
 Control('missing u','u',nil,false);Control('changed u','u',(tonumber(payload.u) or 0)+1,false);Control('mistyped u','u',tostring(payload.u),false)
 if pageId==nil then
  Control('unexpected b','b',other,false)
 else
  Control('missing b','b',nil,false);Control('wrong b','b',other,false)
 end
 Control('mistyped b','b',{},false)
 return failed
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
 C.setup(type(row)=='table' and row.dps==4000 and type(row.lockedEchoes)=='table' and #row.lockedEchoes==1,
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
 local first=payloads[1]
 C.guard(#payloads>0 and type(first)=='table' and type(first.e)=='table' and #first.e==1
  and type(first.lk)=='table' and #first.lk==1,
  'D23: decoded real record carries ordinary and nonempty locked Echoes')
 -- Wire fields of that original unsolicited record (GUARD). CommitSession
 -- serialized it before its retained page commit, with no verified page of
 -- this set in the fresh catalog, so b is absent (never inferred from the
 -- page that exists later); r, l and u are the captured realm, level and
 -- duration under Sync's normalization.
 C.setup(type(row.realm)=='string' and tonumber(row.level)==H.playerLevel and tonumber(row.duration)~=nil,
  'D23: the captured row carries its realm, level and duration',printable(row.realm))
 local wireOk,wireWhy=RecordWireFields(first,row,nil)
 print('OBSERVED','D23','wire r='..printable(first and first.r),'l='..printable(first and first.l),
  'u='..printable(first and first.u),'b='..printable(first and first.b))
 C.guard(wireOk,'D23: the original record carries the captured realm, level and duration and no b',wireWhy)
 local wrong=RecordWireControls(first,row,nil,page.id)
 C.guard(#wrong==0,'D23: the wire-field oracle refuses missing, changed or mistyped r/l/u and an unexpected b',table.concat(wrong,'; '))

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
 -- D23 exact rows: the captured record's own lists are retained here, before
 -- the fresh boot (not the payload's claims), as the producer expectation that
 -- every decoded WLD2 payload and the received DPS record are compared with;
 -- the literal pins (D23_RAW, D23_PAGE, D23_DRAFT) are checked independently.
 -- Each pin first accepts its own known-good rows and refuses same-count
 -- controls that the existing count checks accept.
 local RAW_O,RAW_L={{spellId=300001,count=1}},{{spellId=300003,count=1}}
 D23Controls('raw',D23_RAW,{RAW_O,RAW_L},{
  {'a wrong ID',{{spellId=300002,count=1}},RAW_L},
  {'wrong copies',{{spellId=300001,count=2}},RAW_L},
  {'a stated quality 0 where the raw form states none (ABSENT vs 0)',{{spellId=300001,quality=0,count=1}},RAW_L},
  {'a stated quality 2 in the raw locked list',RAW_O,{{spellId=300003,quality=2,count=1}}},
  {'swapped roles',RAW_L,RAW_O},
  {'a locked marker in the ordinary list',{{spellId=300001,count=1,locked=true}},RAW_L},
  {'an ordinary marker in the locked list',RAW_O,{{spellId=300003,count=1,sourceRole='ordinary'}}},
  {'a missing locked list',RAW_O,nil},
  {'a non-dense ordinary list',{[2]={spellId=300001,count=1}},RAW_L},
  {'an invalid count',{{spellId=300001,count=0}},RAW_L}})
 local PAGE_O,PAGE_L={{spellId=300001,quality=0,stacks=1}},{{spellId=300003,quality=0,stacks=1,locked=true}}
 D23Controls('canonical page',D23_PAGE,{PAGE_O,PAGE_L},{
  {'a missing stored locked list',PAGE_O,nil},
  {'an empty stored locked list',PAGE_O,{}},
  {'a non-dense stored locked list',PAGE_O,{[2]={spellId=300003,quality=0,stacks=1,locked=true}}},
  {'a second stored locked row',PAGE_O,{PAGE_L[1],{spellId=300002,quality=0,stacks=1,locked=true}}},
  {'an absent ordinary quality (ABSENT vs 0)',{{spellId=300001,stacks=1}},PAGE_L},
  {'an absent locked quality (ABSENT vs 0)',PAGE_O,{{spellId=300003,stacks=1,locked=true}}},
  {'a wrong canonical ordinary quality (the catalog 2)',{{spellId=300001,quality=2,stacks=1}},PAGE_L},
  {'a wrong canonical locked quality (the catalog 2)',PAGE_O,{{spellId=300003,quality=2,stacks=1,locked=true}}},
  {'a wrong ID',{{spellId=300002,quality=0,stacks=1}},PAGE_L},
  {'wrong copies',PAGE_O,{{spellId=300003,quality=0,stacks=2,locked=true}}},
  {'swapped roles',{{spellId=300003,quality=0,stacks=1}},{{spellId=300001,quality=0,stacks=1,locked=true}}}})
 local DRAFT_O={{spellId=300001,quality=2,stacks=1,sourceRole='ordinary'}}
 local DRAFT_L={{spellId=300003,quality=0,stacks=1,locked=true,sourceRole='locked'}}
 D23Controls('copied draft',D23_DRAFT,{DRAFT_O,DRAFT_L},{
  {'a missing copied ordinary quality',{{spellId=300001,stacks=1,sourceRole='ordinary'}},DRAFT_L},
  {'the canonical 0 instead of the copied ordinary quality 2',{{spellId=300001,quality=0,stacks=1,sourceRole='ordinary'}},DRAFT_L},
  {'a wrong copied ordinary quality 3',{{spellId=300001,quality=3,stacks=1,sourceRole='ordinary'}},DRAFT_L},
  {'a missing copied locked quality',DRAFT_O,{{spellId=300003,stacks=1,locked=true,sourceRole='locked'}}},
  {'the earlier unsupported locked quality 2',DRAFT_O,{{spellId=300003,quality=2,stacks=1,locked=true,sourceRole='locked'}}},
  {'a wrong ID',{{spellId=300002,quality=2,stacks=1,sourceRole='ordinary'}},DRAFT_L},
  {'wrong copies',DRAFT_O,{{spellId=300003,quality=0,stacks=2,locked=true,sourceRole='locked'}}},
  {'swapped roles',{{spellId=300003,quality=0,stacks=1,sourceRole='ordinary'}},{{spellId=300001,quality=2,stacks=1,locked=true,sourceRole='locked'}}},
  {'an ordinary row marked locked',{{spellId=300001,quality=2,stacks=1,sourceRole='locked'}},DRAFT_L},
  {'a locked row marked ordinary',DRAFT_O,{{spellId=300003,quality=0,stacks=1,sourceRole='ordinary'}}}})
 local captured,whyCaptured=D23Exact(row.echoes,row.lockedEchoes)
 print('OBSERVED','D23','captured rows='..D23Text(captured))
 C.setup(captured~=nil and expectedOrdinary=='300001x1' and expectedLocked=='300003x1',
  'D23: the captured record holds ordinary 300001 x1 and locked 300003 x1',printable(whyCaptured or D23Text(captured)))
 local okCapture,whyCapture=D23Match(row.echoes,row.lockedEchoes,D23_RAW)
 C.guard(okCapture,'D23: raw pin: the captured record states ordinary 300001 x1 and locked 300003 x1 with quality ABSENT (DpsCapture snapshots carry IDs and counts only)',whyCapture)
 local okWire,whyWire=#payloads>0,'no complete transmission'
 local okWireRaw,whyWireRaw=okWire,whyWire
 for _,payload in ipairs(payloads) do
  local same,detail=D23Match(payload.e,payload.lk,captured)
  if not same then okWire,whyWire=false,detail end
  same,detail=D23Match(payload.e,payload.lk,D23_RAW)
  if not same then okWireRaw,whyWireRaw=false,detail end
 end
 C.guard(okWire,'D23: every decoded WLD2 carries exactly the captured ordinary and locked rows (ID, copies, role and quality, each exactly)',whyWire)
 C.guard(okWireRaw,'D23: raw pin: every decoded WLD2 states ordinary 300001 x1 and locked 300003 x1 with quality ABSENT',whyWireRaw)
 local senderOwner=Nexus.Identity.VerifiedOwnerKey(row)
 C.setup(senderOwner~=nil and senderOwner==Nexus.Identity.OwnerKey(SUPPORTED.name,GetRealmName()),
  'D23: the captured record has its sender\'s verified owner',senderOwner)
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
 -- The receiver's own records: the received DPS record against the retained
 -- capture and the raw pin (quality ABSENT), and the stored page against the
 -- canonical pin alone: both of its lists present, dense and one exact row
 -- each, at quality 0. The received record and the stored page each state the
 -- sender's verified owner, present and equal (a nil owner never passes).
 local okDps,whyDps=D23Match(received and received.echoes,received and received.lockedEchoes,captured)
 C.guard(okDps,'D23: the received DPS record holds exactly the captured ordinary and locked rows (ID, copies, role and quality, each exactly)',whyDps)
 local okDpsRaw,whyDpsRaw=D23Match(received and received.echoes,received and received.lockedEchoes,D23_RAW)
 C.guard(okDpsRaw,'D23: raw pin: the received DPS record states ordinary 300001 x1 and locked 300003 x1 with quality ABSENT',whyDpsRaw)
 local pageLocked=stored and stored.lockedEchoes
 local okPage,whyPage=D23Match(stored and stored.echoes,pageLocked,D23_PAGE)
 print('OBSERVED','D23','page locked list='..printable(type(pageLocked)=='table' and #pageLocked or pageLocked),'page rows='..printable(whyPage))
 C.guard(okPage,'D23: canonical page pin: the stored page states both lists, dense, each one exact row: ordinary 300001 x1 and locked 300003 x1 at quality 0 (the canonical default; not an unknown sentinel, not owned Common)',whyPage)
 local receivedOwner=received and Nexus.Identity.VerifiedOwnerKey(received)
 local pageOwner=stored and Nexus.Identity.VerifiedOwnerKey(stored)
 print('OBSERVED','D23','received verified owner='..printable(receivedOwner),'page verified owner='..printable(pageOwner))
 C.guard(D23Owner(receivedOwner,senderOwner),'D23: the received DPS record keeps the sender\'s verified owner',printable(receivedOwner))
 C.guard(D23Owner(pageOwner,senderOwner),'D23: the stored page states the sender\'s verified owner, present and equal to the sender',printable(pageOwner))
 -- Controls of the owner oracle: the sender passes; a nil owner (also against
 -- a nil sender), another owner and each real record read without its
 -- verification (Identity.VerifiedOwnerKey on a copy) are refused.
 local otherOwner=Nexus.Identity.OwnerKey('Pagereceiver',GetRealmName())
 local ownerWrong={}
 local function OwnerControl(label,actual,accept)
  if D23Owner(actual,senderOwner)~=accept then ownerWrong[#ownerWrong+1]=label end
 end
 OwnerControl('the sender',senderOwner,true)
 OwnerControl('a nil owner',nil,false)
 OwnerControl('another owner',otherOwner,false)
 if D23Owner(nil,nil) then ownerWrong[#ownerWrong+1]='a nil owner against a nil sender' end
 for _,source in ipairs({{'received record',received},{'stored page',stored}}) do
  if type(source[2])=='table' then
   local copy={}
   for k,v in pairs(source[2]) do copy[k]=v end
   copy.ownerVerified=nil
   OwnerControl('the '..source[1]..' without its verification',Nexus.Identity.VerifiedOwnerKey(copy),false)
  end
 end
 C.guard(#ownerWrong==0 and otherOwner~=nil and otherOwner~=senderOwner,
  'D23: the owner oracle accepts the sender and refuses a nil, unverified or other owner',table.concat(ownerWrong,'; '))
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
  -- The draft that real Copy made, read through the editor's own controller
  -- as wishlist_editor_binding finds it (read only): its pending rows are the
  -- ordinary role, its pending-lock rows the locked role, and it adds no
  -- fulfilled target. Quality is the copied draft pin (D23_DRAFT) under the
  -- public NormalizeCandidateEvidence policy: ordinary 2 is catalog
  -- enrichment, tied below to the receiver catalog's metadata (SETUP), and
  -- locked 0 is tied to the stored page's canonical 0. The ties are
  -- equalities only: neither value is owned rarity, and which list Copy read
  -- is not asserted.
  local controller
  for i=1,255 do
   local n,v=debug.getupvalue(Nexus.WishlistEditor.Show,i)
   if not n then break end
   if n=='wishlistController' then controller=v;break end
  end
  local function Values(map)
   if type(map)~='table' then return nil end
   local out={}
   for _,v in pairs(map) do out[#out+1]=v end
   return out
  end
  local okCat,receiverCatalog=pcall(function() return A.Catalog() end)
  local catalogRows=okCat and type(receiverCatalog)=='table' and type(receiverCatalog.rows)=='table' and receiverCatalog.rows or {}
  local catalogOrdinary=type(catalogRows[300001])=='table' and catalogRows[300001].quality or nil
  local catalogLocked=type(catalogRows[300003])=='table' and catalogRows[300003].quality or nil
  C.setup(catalogOrdinary==2 and catalogLocked==2,
   'D23: fixture metadata: the receiver catalog lists 300001 and 300003 at catalog quality 2 (H.AddEcho; metadata, not owned rarity)',
   printable(catalogOrdinary)..'/'..printable(catalogLocked))
  local okDraft,whyDraft=false,'editor controller not found'
  local pendingList,lockList
  if controller then
   pendingList,lockList=Values(controller.PendingRows()),Values(controller.PendingLockRows())
   okDraft,whyDraft=D23Match(pendingList,lockList,D23_DRAFT)
  end
  C.guard(okDraft and draft.fulfilled==0,
   'D23: copied draft pin: exactly ordinary 300001 x1 quality 2 (catalog-enriched) and locked 300003 x1 quality 0 (canonical), each in its own role, no fulfilled target',
   printable(whyDraft)..' fulfilled='..printable(draft.fulfilled))
  local function Only(list) return type(list)=='table' and #list==1 and type(list[1])=='table' and list[1] or nil end
  local draftOrdinary,draftLocked,pageLockedRow=Only(pendingList),Only(lockList),Only(pageLocked)
  C.guard(draftOrdinary~=nil and catalogOrdinary~=nil and draftOrdinary.quality==catalogOrdinary,
   'D23: tie: the copied ordinary quality equals the receiver catalog metadata of 300001 (catalog enrichment, not owned rarity)',
   printable(draftOrdinary and draftOrdinary.quality)..'/'..printable(catalogOrdinary))
  C.guard(draftLocked~=nil and pageLockedRow~=nil and pageLockedRow.quality==0 and draftLocked.quality==pageLockedRow.quality,
   'D23: tie: the copied locked quality equals the stored page\'s canonical 0 (an equality only: not owned rarity, no claim which list Copy read)',
   printable(draftLocked and draftLocked.quality)..'/'..printable(pageLockedRow and pageLockedRow.quality))
 end
 C.guard(#H.actions==0,'D23: receiver performs no game action',#H.actions)
end)

-- D23 positive page link (GUARD; SETUP for the fixture). A first new best
-- creates its automatic page through the real capture and lets it commit.
-- Once the public readers (BuildCatalog.Get and FindExactFingerprint, the
-- Identity ordinary-mirror and verified-owner readers, the captured
-- fingerprint and Echo set) show that page as this character's current exact
-- page, a strictly better best on the same set begins with it (CommitSession
-- FindMatchingBuild; EnsureDpsBuildForEchoes returns it) and Sync sends it as
-- b. Only the WLD2 sent after the second capture is reassembled. Nothing is
-- injected, stubbed or forced; if the page is not established the scenario
-- reports the blocker and asserts no b.
C.scenario('D23B a better best on the same Echo set links its verified page',function()
 Boot(nil,SUPPORTED)
 UseEchoes(300001)
 local catalog,identity=Nexus.BuildCatalog,Nexus.Identity
 local sent0=#H.sent
 local ok,err=Capture(90000)
 C.setup(ok,'D23B: first qualifying capture completed',err)
 local row=D.GetCurrentPersonalBest('dummy')
 C.setup(type(row)=='table' and row.dps==3000 and type(row.fingerprint)=='string',
  'D23B: the first capture committed a new personal best',row and row.dps)
 Until(2000,function() return AutoSummary(0)~=nil end)
 local page=AutoSummary(0)
 C.setup(page~=nil and type(page.id)=='string','D23B: the first capture created its page')
 if not page or type(page.id)~='string' or type(row)~='table' or type(row.fingerprint)~='string' then return end
 C.setup(Until(1200,function()
  local t,id=Traffic(sent0,page,row)
  return #(Complete(t.transfers[tostring(id)]))>0
 end),'D23B: the first record transfer left before the second capture')
 local function Verified()
  local okRead,result=pcall(function()
   local built=catalog.Get(page.id)
   local exactId,exact=catalog.FindExactFingerprint(row.fingerprint)
   return type(built)=='table' and type(exact)=='table' and exactId==page.id
    and identity.SavedMirrorKind(built)=='ordinary' and identity.SavedMirrorKind(exact)=='ordinary'
    and row.ownerKey~=nil and identity.VerifiedOwnerKey(built)==row.ownerKey
    and identity.VerifiedOwnerKey(exact)==row.ownerKey
    and (built.fingerprint==nil or built.fingerprint==row.fingerprint)
    and EchoList(built.echoes)==EchoList(row.echoes)
  end)
  return okRead and result==true
 end
 Until(400,Verified)
 local established=Verified()
 C.setup(established,'D23B: the committed page is the current exact, ordinary, verified-own page of the captured Echo set',page.id)
 if not established then
  print('BLOCKED','D23B','no verified ordinary page of the captured set was established; no b is asserted')
  return
 end
 local sent1=#H.sent
 ok,err=Capture(120000)
 C.setup(ok,'D23B: second qualifying capture completed',err)
 local second=D.GetCurrentPersonalBest('dummy')
 local better=type(second)=='table' and second.dps==4000 and second.fingerprint==row.fingerprint
 C.setup(better,'D23B: it committed a strictly better personal best on the same exact set',second and second.dps)
 if not better then return end
 C.setup(type(second.realm)=='string' and tonumber(second.level)==H.playerLevel and tonumber(second.duration)~=nil,
  'D23B: the captured row carries its realm, level and duration',printable(second.realm))
 Until(1200,function()
  local t,id=Traffic(sent1,page,second)
  return #(Complete(t.transfers[tostring(id)]))>0
 end)
 local traffic,transferId=Traffic(sent1,page,second)
 RecordGuards('D23B',traffic,transferId,second,page)
 C.guard(second.buildId==page.id,'D23B: the better row links the verified page it began with',printable(second.buildId))
 local payload=Complete(traffic.transfers[tostring(transferId)])[1]
 local wireOk,wireWhy=RecordWireFields(payload,second,page.id)
 print('OBSERVED','D23B','wire r='..printable(payload and payload.r),'l='..printable(payload and payload.l),
  'u='..printable(payload and payload.u),'b='..printable(payload and payload.b),'page='..printable(page.id))
 C.guard(wireOk,'D23B: the new WLD2 carries the captured realm, level and duration, and b is that verified page',wireWhy)
 local wrong=RecordWireControls(payload,second,page.id)
 C.guard(#wrong==0,'D23B: the wire-field oracle refuses missing, wrong or mistyped b, realm, level and duration',table.concat(wrong,'; '))
end)

-- D23Q public typed known-quality control (GUARD; SETUP for the fixture).
-- The public pure WishlistModel.New().NormalizeCandidateEvidence is called
-- directly (no wire, page or Copy) with literal typed rows, ordinary
-- {spellId=300001,quality=2,stacks=1} and locked {spellId=300003,quality=Q,
-- stacks=1}, the real boot catalog (Adapter.Catalog(); H.AddEcho registers
-- both at catalog quality 2) and no locked-owned spell. A stated locked 3
-- surviving the catalog 2 discriminates preservation from catalog fallback;
-- a stated 2 alone cannot, and a stated 0 stays a valid stated 0. Separately:
-- an unstated locked quality takes the catalog 2, and an ordinary row takes
-- the catalog 2 even when it states 3 (ordinary is catalog-first; nothing
-- here says ordinary keeps a stated quality). A stated locked -1 or 1.5 forms
-- no draft. Typed-contract GUARDs only: no wire, native or owned-rarity
-- claim, and no behavior repair.
C.scenario('D23Q public typed known-quality control through NormalizeCandidateEvidence',function()
 Boot(nil,SUPPORTED)
 C.setup(Nexus.StartupStatus().state=='ready','D23Q: fixture: start-up ready')
 local okModel,model=pcall(function() return Nexus.WishlistModel.New() end)
 local normalize=okModel and type(model)=='table' and model.NormalizeCandidateEvidence or nil
 C.setup(type(normalize)=='function','D23Q: fixture: the public WishlistModel.New() exposes NormalizeCandidateEvidence',printable(type(normalize)))
 local okCat,catalog=pcall(function() return A.Catalog() end)
 local rows=okCat and type(catalog)=='table' and type(catalog.rows)=='table' and catalog.rows or {}
 local q1=type(rows[300001])=='table' and rows[300001].quality or nil
 local q3=type(rows[300003])=='table' and rows[300003].quality or nil
 C.setup(q1==2 and q3==2,'D23Q: fixture metadata: the boot catalog lists 300001 and 300003 at catalog quality 2 (H.AddEcho; metadata, not owned rarity)',
  printable(q1)..'/'..printable(q3))
 if type(normalize)~='function' or q1~=2 or q3~=2 then return end
 local function Typed(ordinaryQuality,lockedQuality)
  return pcall(normalize,{{spellId=300001,quality=ordinaryQuality,stacks=1}},
   {{spellId=300003,quality=lockedQuality,stacks=1}},{catalog=catalog,lockedBySpell={}})
 end
 local function Rows(map)
  if type(map)~='table' then return nil end
  local out={}
  for _,v in pairs(map) do out[#out+1]=v end
  return out
 end
 local function Draft(label,ordinaryQuality,lockedQuality,expectOrdinary,expectLocked)
  local ok,prepared,why=Typed(ordinaryQuality,lockedQuality)
  local same,detail,shape=false,ok and printable(why or 'no draft') or 'raised: '..printable(prepared),false
  if ok and type(prepared)=='table' then
   local pending,lock=Rows(prepared.pending),Rows(prepared.pendingLock)
   same,detail=D23Match(pending,lock,{D23Row(300001,1,expectOrdinary,'ordinary'),D23Row(300003,1,expectLocked,'locked')})
   local o,l=type(pending)=='table' and #pending==1 and pending[1],type(lock)=='table' and #lock==1 and lock[1]
   shape=type(o)=='table' and o.sourceRole=='ordinary' and o.locked==nil and o.stacks==1
    and type(l)=='table' and l.sourceRole=='locked' and l.locked==true and l.stacks==1
    and type(prepared.fulfilledTargets)=='table' and next(prepared.fulfilledTargets)==nil
  end
  print('OBSERVED','D23Q',label,'rows='..printable(detail),'roles, one copy, no fulfilled target='..printable(shape))
  C.guard(same and shape,'D23Q: '..label..', each row in its own role with one copy and no fulfilled target',printable(detail))
 end
 Draft('a stated locked quality 3 survives the catalog 2 (discriminating)',2,3,2,3)
 Draft('a stated locked quality 2 stays 2 (alone not discriminating: it equals the catalog 2)',2,2,2,2)
 Draft('a stated locked quality 0 stays 0 (a valid stated 0)',2,0,2,0)
 Draft('an unstated locked quality takes the catalog 2',2,nil,2,2)
 Draft('an ordinary row stating 3 takes the catalog 2 (catalog-first) while the stated locked 3 stays',3,3,2,3)
 for _,q in ipairs({-1,1.5}) do
  local ok,prepared,why=Typed(2,q)
  C.guard(ok and prepared==nil and why=='locked Echo evidence is invalid',
   'D23Q: a stated locked quality '..tostring(q)..' is refused and forms no draft',ok and printable(why) or 'raised: '..printable(prepared))
 end
 C.guard(#H.actions==0,'D23Q: no game action',#H.actions)
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
