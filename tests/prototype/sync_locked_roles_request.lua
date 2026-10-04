-- User-requested locked-role completion ("Request full build";
-- docs/P1_7_LOCKED_ROLE_WIRE.md). A peer holds a verified owner's build whose
-- locked roles are unknown (it arrived through a released peer). One
-- deliberate request queues one exact-ID loadout request with our capability
-- stated; only the owner's own same-revision full answer completes the
-- record in place. Reading the state sends nothing; nothing retries by
-- itself. Two isolated production runtimes (sync_pair_support.lua); a
-- released peer runs the verbatim test.9049 files. Synthetic data only.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Rows(list)
 local out={}
 for _,r in ipairs(list) do out[#out+1]={spellId=r[1],quality=r[2],stacks=r[3],locked=r[4] or nil} end
 return out
end
local function Slots(name,rows) return {[102]={name='NEXUS-TEST-'..name,verified=false,echoes=Rows(rows)}} end
local function Key(rows)
 local t={}
 for _,r in ipairs(rows or {}) do t[#t+1]=string.format('%d:%d:%d',r.spellId or r.id,r.quality or 0,r.stacks or r.count or 1) end
 table.sort(t);return table.concat(t,',')
end
local function Copy(v,seen)
 if type(v)~='table' then return v end
 seen=seen or {};if seen[v] then return seen[v] end
 local o={};seen[v]=o
 for k,x in pairs(v) do o[Copy(k,seen)]=Copy(x,seen) end
 return o
end
local function From(saved) return function(db) for k in pairs(db) do db[k]=nil end;for k,v in pairs(Copy(saved)) do db[k]=v end end end
local function Configure(list) return function(i,db) if list[i] then list[i](db) end end end
local function Get(p,id) return p.e.Nexus.BuildCatalog.Get(id) end
local function Unknown(row) return row and row.lockedEchoes==nil and row.lockedAuthorityProven~=true end
-- Packets a peer has handed to its transport (delivered or still held).
local function Sent(p,code)
 local n=0
 for _,packet in ipairs(p.H.sent) do
  local c=tostring(packet.text or ''):gsub('||','|'):match('^([^|]+)')
  if c and c:gsub('^P%d+:','')==code then n=n+1 end
 end
 return n
end
local MIXED={{200001,1,3},{200002,2,1},{200085,1,1,true},{200086,2,1,true}}
local ORDINARY='200001:1:3,200002:2:1'
local LOCKED='200085:1:1,200086:2:1'

-- Fixture: Alpha (current) shares; the released peer Rel stores it with
-- unknown roles. Alpha also answers a capable third peer, so a full answer
-- (lv=1) of this revision exists in the trace for the relay case below.
local savedAlpha,savedRel,id,fullAnswer
do
 P.Boot({'Alpha','Rel'},5,nil,{slots={Slots('Alpha',MIXED),nil},released={nil,true}})
 id=P.Post(P.A,'Requested roles')
 P.Until(function() return Get(P.A,id)~=nil end)
 P.Until(function() return P.Full(P.B,id) end)
 local S=P.A.e.Nexus.Sync
 assert(S.HandleIncoming('WLCP|Charlie-Ebonhold|lv1|charlie00001','Charlie-Ebonhold'))
 S.HandleIncoming('WLLQ|Charlie-Ebonhold|'..id,'Charlie-Ebonhold')
 for _=1,600 do P.Step() end
 -- Group the owner's answer chunks (i/n) and keep one complete full answer.
 local group
 for _,t in ipairs(P.trace) do
  if t.code=='WLRB' and t.from==P.A.name and not fullAnswer then
   local text=t.text:gsub('||','|'):gsub('^P%d+:','')
   local f={};for field in (text..'|'):gmatch('([^|]*)|') do f[#f+1]=field end
   local i,n=tostring(f[5]):match('^(%d+)/(%d+)$')
   if f[3]==id and i then
    if i=='1' then group={texts={},data={},n=tonumber(n)} end
    if group then
     group.texts[#group.texts+1]=t.text;group.data[#group.data+1]=f[6]
     if #group.texts==group.n then
      local C=P.A.e.Nexus.Codec
      local ok,payload=pcall(function() return C.JSONDecode(C.Base64Decode(table.concat(group.data))) end)
      if ok and type(payload)=='table' and payload.lv==1 then fullAnswer=group.texts end
      group=nil
     end
    end
   end
  end
 end
 check(fullAnswer~=nil,'fixture: the owner sent a full answer (lv=1) for a capable requester')
 check(Unknown(Get(P.B,id)),'fixture: the released peer stores the record with unknown roles')
 savedAlpha,savedRel=Copy(P.A.e.NexusDB),Copy(P.B.e.NexusDB)
end
-- The released profile reopened by a current client; both online.
local function Reopen()
 P.Boot({'Alpha','Rel'},5,Configure({From(savedAlpha),From(savedRel)}),{slots={Slots('Alpha',MIXED),nil}})
 for _=1,200 do P.Step() end
 local held=Get(P.B,id)
 check(held and Key(held.echoes)==ORDINARY and Unknown(held) and held.ownerVerified==true,
  'fixture: the current client holds the verified record with unknown roles')
 return held
end

-- 1. A relay's full answer never completes the record: only the owner may.
local function LogCount(p,needle)
 local n=0
 for _,e in ipairs(p.e.Nexus.Sync.EventLog() or {}) do
  local text=type(e)=='table' and tostring(e.text or e.msg or e[2] or '') or tostring(e)
  if text:find(needle,1,true) then n=n+1 end
 end
 return n
end
do
 Reopen()
 local needle="REJECT relayed overwrite of '"..id.."'"
 local r0=LogCount(P.B,needle)
 for _,text in ipairs(fullAnswer) do
  local relayed,n=text:gsub('WLRB||Alpha||','WLRB||Charlie||',1)
  check(n==1,'fixture: the relayed copy names another sender')
  P.Channel(P.B,relayed,'Charlie-Ebonhold')
 end
 for _=1,200 do P.Step() end
 check(Unknown(Get(P.B,id)),'a full answer relayed by another peer does not complete the owner record')
 check(LogCount(P.B,needle)>r0,'the relayed answer was received and refused as a relayed overwrite')
end

-- 2. Reading the state and refused requests send nothing.
do
 local held=Reopen()
 local S=P.B.e.Nexus.Sync
 local q0,c0=Sent(P.B,'WLLQ'),Sent(P.B,'WLCP')
 for _=1,40 do check(S.LockedRolesRequestStatus(id)==nil,'no request was made: no state');P.Step() end
 local function Refused(state,reasonPart,label,targetId)
  local ok,got,why=S.RequestLockedRoles(targetId or id)
  check(ok==false and got==state and tostring(why):find(reasonPart,1,true),label..': '..tostring(got)..' / '..tostring(why))
 end
 local policy=P.B.e.Nexus.SyncModePolicy;local mode=policy.Mode
 policy.Mode=function() return 'off' end
 Refused('refused','Sync is Off','Sync Off refuses the request')
 policy.Mode=function() return 'manual' end
 Refused('refused','Manual mode','Manual mode without Sync Now refuses the request')
 policy.Mode=mode
 local connected=S.IsConnected
 S.IsConnected=function() return false end
 Refused('offline','not connected','no sync channel: offline')
 S.IsConnected=connected
 Refused('refused','not in your library','an unknown build is refused','missing-build-id')
 local own=P.A.e.Nexus.Sync
 local ok,state,why=own.RequestLockedRoles(id)
 check(ok==false and state=='refused' and tostring(why):find('your own build',1,true),'the owner cannot request its own build: '..tostring(why))
 -- An unverified (relayed) record of the same character is refused.
 local C=P.B.e.Nexus.BuildCatalog
 local rec={id='relayed-unverified-1',title='Relayed build',author='Alpha',ownerKey='alpha@ebonhold',realm='ebonhold',class='MAGE',
  postedAt=held.postedAt,lastModified=held.lastModified,description='Relayed',echoes=Copy(held.echoes)}
 local stored,storedWhy,ticket=C.Put(rec,{source='remote',sender='Relayer-Ebonhold'})
 if stored==nil and type(ticket)=='table' then
  for _=1,4000 do if ticket.state~='pending' then break end;P.Step() end
 end
 local unverified=Get(P.B,'relayed-unverified-1')
 check(unverified and unverified.ownerVerified==false,'fixture: a relayed record without an established owner')
 Refused('refused','not verified','an unverified owner is refused','relayed-unverified-1')
 for _=1,200 do P.Step() end
 check(Sent(P.B,'WLLQ')==q0 and Sent(P.B,'WLCP')==c0,'state reads and refusals send no request and no capability')
end

-- 3. One deliberate request: our capability, one exact-ID request, the
-- owner's full answer, the record completed in place; then idempotent.
do
 local held=Reopen()
 local S=P.B.e.Nexus.Sync
 local q0,c0,a0=Sent(P.B,'WLLQ'),Sent(P.B,'WLCP'),Sent(P.A,'WLRB')
 local ok,state=S.RequestLockedRoles(id)
 check(ok==true and state=='pending','the request is queued: '..tostring(state))
 local again,againState=S.RequestLockedRoles(id)
 check(again==false and againState=='pending','a second click while waiting adds nothing: '..tostring(againState))
 check(S.LockedRolesRequestStatus(id)=='pending','state: pending')
 P.Until(function() local r=Get(P.B,id);return r and r.lockedAuthorityProven==true end,4000)
 local now=Get(P.B,id)
 check(Key(now.lockedEchoes)==LOCKED,'the owner states the exact locked targets: '..Key(now.lockedEchoes))
 check(now.lastModified==held.lastModified and now.fingerprint==held.fingerprint and Key(now.echoes)==ORDINARY
  and now.ownerKey==held.ownerKey and now.ownerVerified==true and now.id==held.id,
  'completed in place: same revision, fingerprint, ordinary targets and verified owner')
 check(Sent(P.B,'WLLQ')-q0==1,'exactly one loadout request: '..(Sent(P.B,'WLLQ')-q0))
 check(Sent(P.B,'WLCP')-c0>=1,'our capability was stated with the request')
 check(Sent(P.A,'WLRB')-a0>=1,'the owner answered')
 check(S.LockedRolesRequestStatus(id)=='complete','state: complete')
 local done,doneState=S.RequestLockedRoles(id)
 check(done==false and doneState=='complete','a later click does not request known roles: '..tostring(doneState))
 -- The same full answer heard again changes nothing.
 local before=Copy(now)
 for _,text in ipairs(fullAnswer) do P.Channel(P.B,text,P.A.name) end
 for _=1,400 do P.Step() end
 local after=Get(P.B,id)
 check(Key(after.lockedEchoes)==Key(before.lockedEchoes) and after.lastModified==before.lastModified
  and after.lockedAuthorityProven==true,'a repeated owner answer is idempotent')
 for _=1,2400 do P.Step() end
 check(Sent(P.B,'WLLQ')-q0==1,'no further request in two minutes')
end

-- 4. The owner reloaded after our last advertisement and before its own
-- next request: the deliberate request still states our capability, so the
-- owner's answer carries the roles.
do
 Reopen()
 P.Rejoin(1)
 local S=P.B.e.Nexus.Sync
 local c0=Sent(P.B,'WLCP')
 local ok=S.RequestLockedRoles(id)
 check(ok==true,'request after the owner reloaded')
 P.Until(function() local r=Get(P.B,id);return r and r.lockedAuthorityProven==true end,4000)
 check(Key(Get(P.B,id).lockedEchoes)==LOCKED,'the reloaded owner answers with the roles')
 local order={}
 for _,t in ipairs(P.trace) do if t.from==P.B.name and (t.code=='WLCP' or t.code=='WLLQ') then order[#order+1]=t.code end end
 check(Sent(P.B,'WLCP')>c0 and order[#order]=='WLLQ' and order[#order-1]=='WLCP',
  'our capability goes immediately before the request: '..table.concat(order,','))
end

-- 5. No answer: the request ends as timeout; nothing is sent again by
-- itself; a new deliberate click may ask once more.
do
 Reopen()
 local S=P.B.e.Nexus.Sync
 -- The owner never hears this peer's request (held, not dropped).
 P.hold=function(p,q,code) return p==P.B and code=='WLLQ' end
 local q0=Sent(P.B,'WLLQ')
 check(S.RequestLockedRoles(id)==true,'request without an answer')
 P.Advance(30)
 check(S.LockedRolesRequestStatus(id)=='pending' and Sent(P.B,'WLLQ')-q0==1,'still waiting after 30 s; one request')
 P.Advance(35)
 local state,why=S.LockedRolesRequestStatus(id)
 check(state=='timeout' and tostring(why):find('no reply',1,true),'after 60 s: timeout: '..tostring(state))
 P.Advance(120)
 check(Sent(P.B,'WLLQ')-q0==1 and Unknown(Get(P.B,id)),'no automatic retry after the timeout')
 local ok,again=S.RequestLockedRoles(id)
 check(ok==true and again=='pending','a new deliberate click may ask again')
 P.Advance(5)
 check(Sent(P.B,'WLLQ')-q0==2,'that click sends exactly one more request')
 P.hold=nil
end

-- 6. The saved mode changes to Off after the click and before the queued
-- request is sent: it is not sent, and the state says so.
do
 Reopen()
 local S=P.B.e.Nexus.Sync
 local q0=Sent(P.B,'WLLQ')
 check(S.RequestLockedRoles(id)==true,'request queued')
 local policy=P.B.e.Nexus.SyncModePolicy;local mode=policy.Mode
 policy.Mode=function() return 'off' end
 P.Advance(5)
 local state,why=S.LockedRolesRequestStatus(id)
 check(state=='refused' and tostring(why):find('Sync mode',1,true),'not sent under the saved mode: '..tostring(state)..' / '..tostring(why))
 check(Sent(P.B,'WLLQ')==q0,'nothing was sent')
 policy.Mode=mode
 P.Advance(120)
 check(Sent(P.B,'WLLQ')==q0 and S.LockedRolesRequestStatus(id)=='refused','no later send by itself')
end

print('PASS sync_locked_roles_request checks='..checks)
