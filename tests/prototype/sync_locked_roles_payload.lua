-- Locked-role payload and capability contract (#73;
-- docs/P1_7_LOCKED_ROLE_WIRE.md). Crafted full-build packets (WLRB) and
-- capability packets (WLCP) go through the real receive path
-- (Sync.HandleIncoming -> inbound -> decoder -> admission -> catalog) of a
-- new peer and of a released test.9049 peer (verbatim fixture files).
-- Expected stored contents are written here, not read from the decoder.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local SENDER='Other-Ebonhold'
local function Key(rows)
 local t={}
 for _,r in ipairs(rows or {}) do t[#t+1]=string.format('%d:%d:%d',r.spellId or r.id,r.quality or 0,r.stacks or r.count or 1) end
 table.sort(t);return table.concat(t,',')
end
local serial=0
-- A full-build payload from SENDER, as its owner, in chunks of the real
-- WLRB form. extra: fields added to the compact object.
local function Payload(peer,extra,e)
 serial=serial+1
 local N=peer.e.Nexus
 local p={id='wire-contract-'..serial,t='Wire contract '..serial,a=SENDER,
  o=N.Identity.OwnerKey('Other','Ebonhold'),c='MAGE',m=1700000000+serial,
  e=e or {{200001,1,3},{200002,2,1}}}
 for k,v in pairs(extra or {}) do p[k]=v end
 return p
end
-- via, optional: a relay that forwards the owner's payload (the transport
-- sender is then not the owner).
local function Deliver(peer,p,via)
 local N=peer.e.Nexus
 local from=via or SENDER
 local b64=N.Codec.Base64Encode(N.Codec.JSONEncode(p))
 local size,chunks=150,{}
 for i=1,#b64,size do chunks[#chunks+1]=b64:sub(i,i+size-1) end
 for i,chunk in ipairs(chunks) do
  N.Sync.HandleIncoming(string.format('WLRB|%s|%s|%d|%d/%d|%s',from,p.id,p.m,i,#chunks,chunk),from)
 end
 -- Admission may be deferred: wait for the stored row, within a bound.
 for _=1,1500 do
  if N.BuildCatalog.Get(p.id) then break end
  P.Step()
 end
 return N.BuildCatalog.Get(p.id)
end
local function Unknown(row) return row.lockedEchoes==nil and row.lockedAuthorityProven~=true end

P.Boot({'Newpeer','Rel'},5,nil,{released={nil,true}})
local NEW,REL=P.A,P.B
check(REL.e.Nexus.OrbGuidance==nil,'fixture: the second peer runs the released build')

-- 1. Stated locked set: known rows.
do
 local got=Deliver(NEW,Payload(NEW,{lv=1,le={{200085,1,1},{200086,2,1}}}))
 check(got and Key(got.echoes)=='200001:1:3,200002:2:1','known: the ordinary targets are stored')
 check(got.lockedAuthorityProven==true and Key(got.lockedEchoes)=='200085:1:1,200086:2:1','known: the stated locked targets are stored')
 local old=Deliver(REL,Payload(REL,{lv=1,le={{200085,1,1},{200086,2,1}}}))
 check(old and Key(old.echoes)=='200001:1:3,200002:2:1' and old.lockedEchoes==nil,'released: the same payload is accepted with the ordinary targets only')
end
-- 2. lv=1 without rows: a known empty locked set (not unknown, not zero rows invented).
do
 local got=Deliver(NEW,Payload(NEW,{lv=1}))
 -- The catalog keeps no empty evidence array: a known empty set is the
 -- proven flag with no locked rows (distinct from unknown: no flag).
 check(got and got.lockedAuthorityProven==true and (got.lockedEchoes==nil or #got.lockedEchoes==0),'known empty: stored as proven with no locked rows')
end
-- 3. No lv: unknown.
do
 local got=Deliver(NEW,Payload(NEW,{}))
 check(got and Unknown(got),'no lv: the locked roles stay unknown')
end
-- 4. A later representation (lv=2): the payload is used; its roles are unknown here.
do
 local got=Deliver(NEW,Payload(NEW,{lv=2,le={{200085,1,1}}}))
 check(got and Key(got.echoes)=='200001:1:3,200002:2:1' and Unknown(got),'lv=2: ordinary targets kept, roles unknown')
end
-- 5. Same ID in both roles: both copies kept, no de-duplication across roles.
do
 local got=Deliver(NEW,Payload(NEW,{lv=1,le={{200001,1,1}}}))
 check(got and Key(got.echoes)=='200001:1:3,200002:2:1' and Key(got.lockedEchoes)=='200001:1:1','dual role: the same ID stays in both roles')
end
-- 6. Refused payloads: nothing stored, for each malformed form.
local refused={
 {'rows without lv',{le={{200085,1,1}}}},
 {'seven locked rows',{lv=1,le={{200085,1,1},{200086,1,1},{200087,1,1},{200088,1,1},{200089,1,1},{200090,1,1},{200084,1,1}}}},
 {'locked copies over 6',{lv=1,le={{200085,1,4},{200086,1,3}}}},
 {'a slot-4 value in a locked row',{lv=1,le={{200085,1,1,1}}}},
 {'zero copies',{lv=1,le={{200085,1,0}}}},
 {'quality over 255',{lv=1,le={{200085,256,1}}}},
 {'a fractional id',{lv=1,le={{200085.5,1,1}}}},
 {'le not an array',{lv=1,le={x=1}}},
}
for _,case in ipairs(refused) do
 local got=Deliver(NEW,Payload(NEW,case[2]))
 check(got==nil,'refused: '..case[1])
end
do
 -- A stated set never mixes with inline slot-4 rows.
 local got=Deliver(NEW,Payload(NEW,{lv=1,le={{200085,1,1}}},{{200001,1,3},{200086,2,1,1}}))
 check(got==nil,'refused: lv=1 together with an inline locked row')
 -- The combined envelope: 79 ordinary copies plus 6 stated locked copies fit
 -- (85); 79 ordinary plus 7 would not (refused above as copies over 6).
 local ordinary={}
 for i=1,79 do ordinary[#ordinary+1]={200000+i,1,1} end
 local ok=Deliver(NEW,Payload(NEW,{lv=1,le={{200085,1,6}}},ordinary))
 check(ok and #ok.echoes==79 and Key(ok.lockedEchoes)=='200085:1:6','the 79 / 6 / 85 envelope holds with the stated set')
end

-- 7. Capability messages: only a well-formed WLCP from the transport sender,
-- stating lv1, makes the new peer answer that requester with the locked set.
local mine,emptyId,unknownId
do
 -- A local record with locked targets on the new peer, answered on request.
 local N=NEW.e.Nexus
 local seeded=Deliver(NEW,Payload(NEW,{lv=1,le={{200085,1,1}}}))
 mine=seeded.id
 emptyId=Deliver(NEW,Payload(NEW,{lv=1})).id
 unknownId=Deliver(NEW,Payload(NEW,{})).id
end
-- The payloads the new peer sent for the record (decoded with its Codec).
local function Answers(target)
 target=target or mine
 local out,parts={}, {}
 for _,pkt in ipairs(NEW.H.sent) do
  local text=(pkt.text or ''):gsub('||','|'):gsub('^P%d+:','')
  local f={};for field in (text..'|'):gmatch('([^|]*)|') do f[#f+1]=field end
  if f[1]=='WLRB' and f[3]==target then
   local i,n=f[5]:match('^(%d+)/(%d+)$')
   local key=f[4];parts[key]=parts[key] or {n=tonumber(n),got={}}
   parts[key].got[tonumber(i)]=f[6]
   local all=parts[key];local done=true
   for k=1,all.n do if not all.got[k] then done=false end end
   if done then out[#out+1]=NEW.e.Nexus.Codec.JSONDecode(NEW.e.Nexus.Codec.Base64Decode(table.concat(all.got)));parts[key]=nil end
  end
 end
 return out
end
local function AnswerTo(requester,capability,target)
 target=target or mine
 local S=NEW.e.Nexus.Sync
 local before=#Answers(target)
 if capability then S.HandleIncoming(capability,requester) end
 S.HandleIncoming('WLLQ|'..requester..'|'..target,requester)
 for _=1,400 do P.Step() end
 local list=Answers(target)
 check(#list>before,'fixture: an answer went out for '..requester)
 return list[#list]
end
local cases={
 {'a well-formed lv1 capability','Cap1-Ebonhold','WLCP|Cap1-Ebonhold|lv1|abcdef123456',true},
 {'lv1 among other tokens','Cap2-Ebonhold','WLCP|Cap2-Ebonhold|zz9,lv1|abcdef123456',true},
 {'no capability','Cap3-Ebonhold',nil,false},
 {'an unknown token only','Cap4-Ebonhold','WLCP|Cap4-Ebonhold|lv9|abcdef123456',false},
 {'a nonce too short','Cap5-Ebonhold','WLCP|Cap5-Ebonhold|lv1|abc',false},
 {'an uppercase nonce','Cap6-Ebonhold','WLCP|Cap6-Ebonhold|lv1|ABCDEF123456',false},
 {'an extra field','Cap7-Ebonhold','WLCP|Cap7-Ebonhold|lv1|abcdef123456|x',false},
 {'another sender name in the message','Cap8-Ebonhold','WLCP|Cap1-Ebonhold|lv1|abcdef123456',false},
}
for _,c in ipairs(cases) do
 local payload=AnswerTo(c[2],c[3])
 if c[4] then
  check(payload.lv==1 and payload.le and #payload.le==1,c[1]..': the answer states the locked set')
 else
  check(payload.lv==nil and payload.le==nil,c[1]..': the answer is ordinary-only')
 end
end
do
 -- A known empty set is restated as known empty (lv=1, no rows) to a
 -- capable requester, and ordinary-only to others.
 local known=AnswerTo('Cap1-Ebonhold','WLCP|Cap1-Ebonhold|lv1|abcdef123456',emptyId)
 check(known.lv==1 and known.le==nil,'known empty relayed as known empty')
 local plain=AnswerTo('Cap3-Ebonhold',nil,emptyId)
 check(plain.lv==nil,'known empty relayed ordinary-only to a requester without the capability')
 -- Unknown roles are never reconstructed by a capable relay.
 local unknown=AnswerTo('Cap1-Ebonhold','WLCP|Cap1-Ebonhold|lv1|abcdef123456',unknownId)
 check(unknown.lv==nil and unknown.le==nil,'unknown roles relayed ordinary-only, even to a capable requester')
end
do
 -- A capability expires: after 900 s without a new advertisement the same
 -- requester gets the ordinary-only answer again.
 P.Advance(905)
 local payload=AnswerTo('Cap1-Ebonhold',nil)
 check(payload.lv==nil,'an expired capability gives an ordinary-only answer')
end

-- 9. Promotion: a relay stated the locked set; the owner's own answer for
-- the same revision replaces the relay's record. Provenance comes first:
-- roles that only the relay stated are not carried into the owner-verified
-- record (unknown, not zero); the owner's full answer then completes it.
do
 P.Boot({'Newpeer','Rel'},5,nil,{released={nil,true}})
 local N=P.A.e.Nexus
 local base=Payload(P.A,{})
 local function With(extra) local c={};for k,v in pairs(base) do c[k]=v end;for k,v in pairs(extra) do c[k]=v end;return c end
 local relayed=Deliver(P.A,With({lv=1,le={{200085,1,1}}}),'Relay-Ebonhold')
 check(relayed and Key(relayed.lockedEchoes)=='200085:1:1','fixture: the relay-stated locked set is stored')
 check(relayed.relaySender~=nil or relayed.claimedOwnerKey~=nil,'fixture: the relay copy is not owner-verified')
 Deliver(P.A,With({}))
 -- Admission may be deferred: wait for the promotion, within a bound.
 for _=1,1500 do local r=N.BuildCatalog.Get(base.id);if r and r.relaySender==nil and r.claimedOwnerKey==nil then break end;P.Step() end
 local promoted=N.BuildCatalog.Get(base.id)
 check(promoted and promoted.relaySender==nil and promoted.claimedOwnerKey==nil,'fixture: the owner answer promoted the record')
 check(promoted and Unknown(promoted),'promotion: relay-only roles are not carried into the owner record: '..Key(promoted and promoted.lockedEchoes))
 Deliver(P.A,With({lv=1,le={{200085,1,1}}}))
 for _=1,1500 do if N.BuildCatalog.Get(base.id).lockedAuthorityProven==true then break end;P.Step() end
 local full=N.BuildCatalog.Get(base.id)
 check(full.lockedAuthorityProven==true and Key(full.lockedEchoes)=='200085:1:1','the full answer from the owner completes the owner record: '..tostring(full.lockedAuthorityProven)..' '..Key(full.lockedEchoes))
end

-- 10. Held admission: the owner's ordinary-only answer and then its full
-- answer for the same revision both wait in the admission queue. The full
-- answer supersedes the held partial one (it is not dropped as a duplicate or
-- an integrity conflict); the reverse order keeps the full answer.
do
 local function Send(peer,p)
  local N=peer.e.Nexus
  local b64=N.Codec.Base64Encode(N.Codec.JSONEncode(p))
  local chunks={}
  for i=1,#b64,150 do chunks[#chunks+1]=b64:sub(i,i+149) end
  for i,chunk in ipairs(chunks) do
   N.Sync.HandleIncoming(string.format('WLRB|%s|%s|%d|%d/%d|%s',SENDER,p.id,p.m,i,#chunks,chunk),SENDER)
  end
 end
 local function Held(first,second)
  P.Boot({'Newpeer','Rel'},5,nil,{released={nil,true}})
  local N=P.A.e.Nexus
  local stats=N.Sync.Stats()
  local superseded0=stats.admissionSuperseded or 0
  local base=Payload(P.A,{})
  local function With(extra) local c={};for k,v in pairs(base) do c[k]=v end;for k,v in pairs(extra) do c[k]=v end;return c end
  -- An earlier build keeps the catalog busy, so both answers are held.
  Send(P.A,Payload(P.A,{}))
  Send(P.A,With(first));Send(P.A,With(second))
  local held=N.BuildCatalog.Get(base.id)==nil
  for _=1,3000 do local r=N.BuildCatalog.Get(base.id);if r and r.lockedAuthorityProven==true then break end;P.Step() end
  return N.BuildCatalog.Get(base.id),held,(stats.admissionSuperseded or 0)-superseded0
 end
 local row,held,superseded=Held({},{lv=1,le={{200085,1,1}}})
 check(held,'fixture: neither answer was stored at once (both held)')
 check(row and row.lockedAuthorityProven==true and Key(row.lockedEchoes)=='200085:1:1','held partial then full: the locked set is stored: '..Key(row and row.lockedEchoes))
 check(superseded==1,'the held partial answer was superseded: '..superseded)
 row,held,superseded=Held({lv=1,le={{200085,1,1}}},{})
 check(held,'fixture: reverse order held too')
 check(row and row.lockedAuthorityProven==true and Key(row.lockedEchoes)=='200085:1:1','held full then partial: the locked set is kept: '..Key(row and row.lockedEchoes))
 check(superseded==0,'held full then partial: the held full answer is not superseded: '..superseded)
end

-- 11. A newer revision never inherits the old revision's locked rows: the
-- owner's full answer for one revision, then its ordinary-only answer for a
-- newer revision (unknown), then a full answer for that newer revision
-- (its own set, not the old one).
do
 P.Boot({'Newpeer','Rel'},5,nil,{released={nil,true}})
 local N=P.A.e.Nexus
 local base=Payload(P.A,{})
 local function With(extra) local c={};for k,v in pairs(base) do c[k]=v end;for k,v in pairs(extra) do c[k]=v end;return c end
 local function Wait(pred) for _=1,3000 do if pred(N.BuildCatalog.Get(base.id)) then break end;P.Step() end;return N.BuildCatalog.Get(base.id) end
 Deliver(P.A,With({lv=1,le={{200085,1,1},{200086,2,1}}}))
 local old=Wait(function(r) return r and r.lockedAuthorityProven==true end)
 check(Key(old.lockedEchoes)=='200085:1:1,200086:2:1','fixture: the first revision holds its stated locked set')
 Deliver(P.A,With({m=base.m+60}))
 local newer=Wait(function(r) return r and r.lastModified==base.m+60 end)
 check(newer.lastModified==base.m+60,'fixture: the newer revision is stored')
 check(Unknown(newer),'a newer ordinary-only revision has unknown roles, not the old rows: '..Key(newer.lockedEchoes))
 Deliver(P.A,With({m=base.m+60,lv=1,le={{200087,1,2}}}))
 local full=Wait(function(r) return r and r.lockedAuthorityProven==true end)
 check(Key(full.lockedEchoes)=='200087:1:2','the newer revision takes its own stated set: '..Key(full.lockedEchoes))
end

-- 8. A read-only (protected) profile hears a full answer: nothing is saved.
do
 P.Boot({'Newpeer','Guarded'},5,function(i,db) if i==2 then db.settingsVersion=99 end end)
 local N=P.B.e.Nexus
 local function Ser(v,seen)
  if type(v)~='table' then return tostring(v) end
  seen=seen or {};if seen[v] then return '<cycle>' end;seen[v]=true
  local keys={};for k in pairs(v) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
  local o={};for _,k in ipairs(keys) do o[#o+1]=tostring(k)..'='..Ser(v[k],seen) end
  return '{'..table.concat(o,',')..'}'
 end
 local before=Ser(P.B.e.NexusDB)
 Deliver(P.B,Payload(P.B,{lv=1,le={{200085,1,1}}}))
 check(Ser(P.B.e.NexusDB)==before,'protected profile: the saved data is unchanged')
end

print('PASS sync_locked_roles_payload checks='..checks)
