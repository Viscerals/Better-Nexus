-- Locked-role wire capability (#73; docs/P1_7_LOCKED_ROLE_WIRE.md).
-- Two isolated production runtimes (sync_pair_support.lua) exchange real
-- packets through their real Share, request, transport, decoder, admission
-- and catalog owners. A "released" peer runs the verbatim test.9049 product
-- files (fixture checked file by file against its MANIFEST). Expected
-- contents are written here from the owner decision, not read back from the
-- encoder. Synthetic data only.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Rows(list)
 local out={}
 for _,r in ipairs(list) do out[#out+1]={spellId=r[1],quality=r[2],stacks=r[3],locked=r[4] or nil} end
 return out
end
local function Slots(name,rows) return {[102]={name='NEXUS-TEST-'..name,verified=false,echoes=Rows(rows)}} end
-- A canonical text of role rows: "id:quality:copies" sorted.
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
-- Boot a peer from a previous peer's saved data (a reload of that profile).
local function From(saved) return function(db) for k in pairs(db) do db[k]=nil end;for k,v in pairs(Copy(saved)) do db[k]=v end end end
local function Configure(list) return function(i,db) if list[i] then list[i](db) end end end
local function Get(p,id) return p.e.Nexus.BuildCatalog.Get(id) end
local function Share(p,title)
 local id=P.Post(p,title)
 P.Until(function() return Get(p,id)~=nil end)
 return id
end
-- A request from a third, synthetic peer, delivered to `peer`'s real
-- receiver (as if heard on the channel). capable: it advertises lv1 first.
local function Ask(peer,requester,id,capable,nonce)
 local S=peer.e.Nexus.Sync
 if capable then assert(S.HandleIncoming('WLCP|'..requester..'|lv1|'..(nonce or 'abcdef123456'),requester)) end
 S.HandleIncoming('WLLQ|'..requester..'|'..id,requester)
end
local function Rejected(p)
 local st=p.e.Nexus.Sync.Stats() or {}
 local n=0;for k,v in pairs(st) do if type(k)=='string' and k:find('reject',1,true) and type(v)=='number' then n=n+v end end
 return n
end
-- Full-build payloads a peer sent (from the bridge trace), decoded with that
-- peer's own Codec: WLRB|sender|id|m|i/n|chunk[|requester|reqId].
local function Payloads(peer,id)
 local parts,out={},{}
 for _,t in ipairs(P.trace) do
  if t.code=='WLRB' and t.from==peer.name then
   local text=t.text:gsub('||','|'):gsub('^P%d+:','')
   local f={};for field in (text..'|'):gmatch('([^|]*)|') do f[#f+1]=field end
   if f[3]==id then
    local i,n=f[5]:match('^(%d+)/(%d+)$')
    local key=f[3]..':'..f[4]
    parts[key]=parts[key] or {n=tonumber(n),got={}}
    parts[key].got[tonumber(i)]=f[6]
    local all=parts[key]
    local done=true;for k=1,all.n do if not all.got[k] then done=false end end
    if done then
     local C=peer.e.Nexus.Codec
     out[#out+1]=C.JSONDecode(C.Base64Decode(table.concat(all.got)))
     parts[key]=nil
    end
   end
  end
 end
 return out
end
local function Unknown(row) return row.lockedEchoes==nil and row.lockedAuthorityProven~=true end

-- 3 ordinary targets and 2 locked targets (the harness's locked pool).
local MIXED={{200001,1,3},{200002,2,1},{200085,1,1,true},{200086,2,1,true}}
local ORDINARY='200001:1:3,200002:2:1'
local LOCKED='200085:1:1,200086:2:1'

-- 1. New -> new: exact ordinary and locked targets; the stored record keeps
-- them across a reload, and a re-export from the reloaded profile to another
-- new peer carries them again.
local savedBravo,idOne
do
 P.Boot({'Alpha','Bravo'},5,nil,{slots={Slots('Alpha',MIXED),nil}})
 idOne=Share(P.A,'Locked roles one')
 local mine=Get(P.A,idOne)
 check(Key(mine.echoes)==ORDINARY and Key(mine.lockedEchoes)==LOCKED,'fixture: the sender record keeps both roles: '..Key(mine.echoes)..' / '..Key(mine.lockedEchoes))
 P.Until(function() return P.Full(P.B,idOne) end)
 local got=Get(P.B,idOne)
 check(Key(got.echoes)==ORDINARY,'new -> new: the ordinary targets arrive: '..Key(got.echoes))
 check(Key(got.lockedEchoes)==LOCKED and got.lockedAuthorityProven==true,'new -> new: the locked targets arrive as known: '..Key(got.lockedEchoes))
 check(P.Count('WLCP')>=1,'fixture: a capability advertisement was sent')
 savedBravo=Copy(P.B.e.NexusDB)
end
do
 P.Boot({'Bravo','Charlie'},5,Configure({From(savedBravo)}))
 local back=Get(P.A,idOne)
 check(back and Key(back.lockedEchoes)==LOCKED and back.lockedAuthorityProven==true,'reload: the stored locked targets stay known: '..Key(back and back.lockedEchoes))
 P.Until(function() return P.Full(P.B,idOne) end)
 local relayed=Get(P.B,idOne)
 check(Key(relayed.echoes)==ORDINARY and Key(relayed.lockedEchoes)==LOCKED,'re-export from the reloaded profile carries the locked targets: '..Key(relayed.lockedEchoes))
end

-- 2. New -> released 9049: the released decoder stores the ordinary targets;
-- the sender counts and states an ordinary-only answer. A capability that a
-- third peer advertised does not change the answer to the released peer.
-- The released peer also hears a full answer (lv/le) meant for that capable
-- third peer: it ignores the new keys, stores the ordinary targets, and drops
-- the capability messages without a rejection.
do
 P.Boot({'Alpha','Rel'},5,nil,{slots={Slots('Alpha',MIXED),nil},released={nil,true}})
 check(P.B.e.Nexus.OrbGuidance==nil and P.A.e.Nexus.OrbGuidance~=nil,'fixture: the second peer runs the released build')
 local rejected0=Rejected(P.B)
 local id=Share(P.A,'Locked roles two')
 Ask(P.A,'Charlie-Ebonhold',id,true)
 P.Until(function() return P.Full(P.B,id) end)
 local got=Get(P.B,id)
 check(Key(got.echoes)==ORDINARY,'new -> released: the ordinary targets arrive: '..Key(got.echoes))
 check(got.lockedEchoes==nil,'new -> released: no locked rows are invented')
 for _=1,200 do P.Step() end
 local status=P.A.e.Nexus.CommunityBuilds.ShareStatus(id)
 check(status and (status.lockedRolesOrdinaryOnly or 0)>=1,'the sender counts an ordinary-only answer: '..tostring(status and status.lockedRolesOrdinaryOnly))
 local _,text=P.A.e.Nexus.CommunityBuilds.ShareStatusText(id)
 check(tostring(text):find('ordinary targets only',1,true)~=nil,'and states it: '..tostring(text))
 local rich,plain=0,0
 for _,payload in ipairs(Payloads(P.A,id)) do
  if payload.lv==1 then rich=rich+1 else plain=plain+1 end
  if payload.lv==1 then check(Key((function() local r={} for _,x in ipairs(payload.le or {}) do r[#r+1]={spellId=x[1],quality=x[2],stacks=x[3]} end return r end)())==LOCKED,'the full answer states the locked set') end
 end
 check(rich>=1 and plain>=1,'fixture: one full answer (for the capable third peer) and one ordinary-only answer (for the released peer) went out: '..rich..'/'..plain)
 check(Key(Get(P.B,id).echoes)==ORDINARY and Get(P.B,id).lockedEchoes==nil,'the released peer still holds the ordinary targets only')
 check(Rejected(P.B)==rejected0,'the released peer rejected nothing (capability messages are dropped silently)')
end

-- 3. Released -> new: the ordinary targets arrive; the locked roles stay
-- UNKNOWN (no rows, not proven), not zero.
do
 P.Boot({'Rel','Bravo'},5,nil,{slots={Slots('Rel',MIXED),nil},released={true,nil}})
 local id=Share(P.A,'Locked roles three')
 check(Key(Get(P.A,id).lockedEchoes)==LOCKED,'fixture: the released sender keeps its locked targets locally')
 P.Until(function() return P.Full(P.B,id) end)
 local got=Get(P.B,id)
 check(Key(got.echoes)==ORDINARY,'released -> new: the ordinary targets arrive: '..Key(got.echoes))
 check(Unknown(got),'released -> new: the locked roles stay unknown, not zero')
 -- A released peer never advertises: its traffic may cause one more
 -- advertisement, not one per request.
 local function Caps() local n=0;for _,t in ipairs(P.trace) do if t.from==P.B.name and t.code=='WLCP' then n=n+1 end end;return n end
 local function Reqs() local n=0;for _,t in ipairs(P.trace) do if t.from==P.B.name and t.code=='WLRQ' then n=n+1 end end;return n end
 local req0=Reqs()
 for _=1,5 do P.B.e.Nexus.Sync.RequestSync();P.Advance(40) end
 check(Reqs()-req0>=3,'fixture: several requests to a released peer within 300 s: '..(Reqs()-req0))
 check(Caps()<=2,'a released peer does not keep the shorter re-advertisement spacing: '..Caps())
end

-- 4. Enrichment, duplicates, a partial answer and a newer revision.
-- A new peer that holds a record with unknown roles (it came through a
-- released peer) hears the owner's full answer for the same revision and
-- completes it. A later ordinary-only answer for the same revision does not
-- erase it. A newer revision answered ordinary-only replaces it with
-- unknown roles; it does not inherit the old rows.
local savedAlpha,savedRel,idFour
do
 P.Boot({'Alpha','Rel'},5,nil,{slots={Slots('Alpha',MIXED),nil},released={nil,true}})
 idFour=Share(P.A,'Locked roles four')
 P.Until(function() return P.Full(P.B,idFour) end)
 savedAlpha,savedRel=Copy(P.A.e.NexusDB),Copy(P.B.e.NexusDB)
end
do
 -- The released profile is now opened by a new client (named Rel).
 P.Boot({'Alpha','Rel'},5,Configure({From(savedAlpha),From(savedRel)}),{slots={Slots('Alpha',MIXED),nil}})
 local held=Get(P.B,idFour)
 check(held and Key(held.echoes)==ORDINARY and Unknown(held),'fixture: the new client holds the record with unknown roles')
 local stamp=held.lastModified
 Ask(P.A,'Charlie-Ebonhold',idFour,true,'charlie00001')
 local ok=pcall(P.Until,function() local r=Get(P.B,idFour);return r and r.lockedAuthorityProven==true end,4000)
 check(ok,'the same revision with its stated locked set completes the record (heard answer from the owner)')
 local now=Get(P.B,idFour)
 check(Key(now.lockedEchoes)==LOCKED and now.lastModified==stamp and Key(now.echoes)==ORDINARY,'enriched: same revision, same ordinary targets, the stated locked targets')
 -- Duplicate: the same full answer again changes nothing.
 local before=Copy(now)
 Ask(P.A,'Charlie-Ebonhold',idFour,true,'charlie00001')
 for _=1,600 do P.Step() end
 local again=Get(P.B,idFour)
 check(Key(again.lockedEchoes)==Key(before.lockedEchoes) and again.lastModified==before.lastModified,'a duplicate full answer changes nothing')
 -- Partial for the same revision: an ordinary-only answer to a requester
 -- without the capability does not erase the known roles.
 Ask(P.A,'Delta-Ebonhold',idFour,false)
 for _=1,600 do P.Step() end
 local kept=Get(P.B,idFour)
 check(Key(kept.lockedEchoes)==LOCKED and kept.lockedAuthorityProven==true,'an ordinary-only answer for the same revision does not erase the known roles')
 -- A newer revision: the stored roles are what the answers for that
 -- revision state, never the old revision's record. The bridge carries every
 -- owner packet to this peer, and this peer is itself a capable requester, so
 -- the owner answers it with a FULL answer for the newer revision as well
 -- (sync_locked_roles_payload 11 fixes that order with crafted packets).
 -- When that full answer lands decides what the replay check below meets. It
 -- used to land whenever the profiler-clock pacing let it: before the
 -- snapshot (the replay then met roles already completed, which a stale
 -- answer can never change anyway), or inside the replay window, where it
 -- completed the same revision legitimately and failed the comparison on
 -- timing alone (no replay is needed for that failure; review-repair evidence).
 -- So the owner's newer FULL answers are held (P.hold: order kept, nothing
 -- dropped, released below) until the replay has been judged. The replay then
 -- always meets the state the revision guard protects -- the newer revision
 -- with unknown roles -- and only the replay can reach the record meanwhile.
 local function Pending(p,index)
  local packet=p.H.sent[index];if not packet then return nil end
  local text=packet.text:gsub('||','|'):gsub('^P%d+:','')
  local f={};for field in (text..'|'):gmatch('([^|]*)|') do f[#f+1]=field end
  if f[1]~='WLRB' then return nil end
  local i,n=(f[5] or ''):match('^(%d+)/(%d+)$')
  return {id=f[3],m=tonumber(f[4]),i=tonumber(i),n=tonumber(n),chunk=f[6],req=f[7]}
 end
 -- The owner's payload that the pending packet belongs to, once all its
 -- chunks were sent (nil while it is still being sent).
 local function PendingPayload(p,index)
  local head=Pending(p,index);local got={}
  for k=index,#p.H.sent do
   local w=Pending(p,k)
   if w and w.id==head.id and w.m==head.m and w.n==head.n and w.req==head.req then got[w.i]=w.chunk end
   local complete=true;for j=1,head.n do if not got[j] then complete=false end end
   if complete then local Codec=p.e.Nexus.Codec;return Codec.JSONDecode(Codec.Base64Decode(table.concat(got))) end
  end
 end
 local holding=true
 P.hold=function(p)
  if p~=P.A or not holding then return false end
  local w=Pending(p,p.cursor+1)
  if not (w and w.id==idFour and w.m and w.m>stamp) then return false end
  local payload=PendingPayload(p,p.cursor+1)
  if payload==nil then return true end
  return payload.lv==1
 end
 local edited=P.A.e.Nexus.CommunityBuilds.EditBuild(idFour,'Locked roles four (edited)','Edited description',nil)
 check(edited,'fixture: the owner edits the build')
 P.Until(function() local r=Get(P.A,idFour);return r and r.lastModified>stamp end)
 local newer=Get(P.A,idFour).lastModified
 Ask(P.A,'Delta-Ebonhold',idFour,false)
 local okNewer=pcall(P.Until,function() local r=Get(P.B,idFour);return r and r.lastModified==newer end,4000)
 check(okNewer,'fixture: the newer revision arrives')
 local last=Get(P.B,idFour)
 check(last.lastModified==newer and Unknown(last),'the newer ordinary-only revision has unknown roles, not the old rows: '..Key(last.lockedEchoes))
 -- Out of order: the older full answer replayed afterwards is ignored. Every
 -- replayed answer must reach the receiver and be refused as stale, and the
 -- record must not change: the older revision does not come back and its
 -- stated roles do not complete the newer revision.
 local Sync=P.B.e.Nexus.Sync
 local skipped0=Sync.Stats().duplicatesSkipped or 0
 local replayed,answers=0,0
 for _,t in ipairs(P.trace) do
  if t.code=='WLRB' and t.from==P.A.name then
   local text=t.text:gsub('||','|'):gsub('^P%d+:','')
   local f={};for field in (text..'|'):gmatch('([^|]*)|') do f[#f+1]=field end
   if f[3]==idFour and tonumber(f[4])==stamp then
    P.Channel(P.B,t.text,P.A.name);replayed=replayed+1
    local i,n=(f[5] or ''):match('^(%d+)/(%d+)$')
    if i and i==n then answers=answers+1 end
   end
  end
 end
 check(replayed>=1 and answers>=1,'fixture: older answers were replayed: '..replayed..' packets, '..answers..' answers')
 for _=1,200 do P.Step() end
 local final=Get(P.B,idFour)
 local refused=(Sync.Stats().duplicatesSkipped or 0)-skipped0
 check(refused>=answers,'every replayed older answer reached the receiver and was refused as stale: '..refused..' of '..answers)
 check(final.lastModified==newer and Key(final.lockedEchoes)==Key(last.lockedEchoes) and final.lockedAuthorityProven==last.lockedAuthorityProven,'an older full answer replayed later does not bring back the old rows')
 -- Released: the owner's held packets arrive in their order, and the newer
 -- revision is completed by its own full answer with the set it states.
 holding=false;P.hold=nil
 local okDone=pcall(P.Until,function() local r=Get(P.B,idFour);return r and r.lockedAuthorityProven==true end,4000)
 check(okDone,'the newer revision is completed by its own full answer once it arrives')
 local statedSet
 for _,payload in ipairs(Payloads(P.A,idFour)) do
  if payload.m==newer and payload.lv==1 then
   local r={};for _,x in ipairs(payload.le or {}) do r[#r+1]={spellId=x[1],quality=x[2],stacks=x[3]} end
   statedSet=Key(r)
  end
 end
 local done=Get(P.B,idFour)
 check(statedSet~=nil and done.lastModified==newer and Key(done.lockedEchoes)==statedSet,'the newer revision holds the set its own answer stated: '..Key(done.lockedEchoes))
end

-- 5. Sync Off: no capability advertisement (and no request) is sent.
do
 P.Boot({'Alpha','Bravo'},5,Configure({nil,function(db) db.settingsVersion=5;db.accountCharacters={};db.settings=db.settings or {};db.settings.syncMode='off' end}),{slots={Slots('Alpha',MIXED),nil}})
 check(P.B.e.Nexus.SyncModePolicy.Mode()=='off','fixture: the saved Sync mode Off is honored')
 local id=Share(P.A,'Locked roles five')
 for _=1,1200 do P.Step() end
 local fromB=0
 for _,t in ipairs(P.trace) do if t.from==P.B.name and (t.code=='WLCP' or t.code=='WLLQ' or t.code=='WLRQ') then fromB=fromB+1 end end
 check(fromB==0,'Sync Off: the peer sends no capability or request: '..fromB)
 check(Get(P.B,id)==nil or not P.Full(P.B,id),'Sync Off: nothing is fetched')
 local fromA=0
 for _,t in ipairs(P.trace) do if t.from==P.A.name and t.code=='WLCP' then fromA=fromA+1 end end
 check(fromA<=2,'the capability is advertised at most once per interval: '..fromA)
end

-- 6. Several requests within the interval: the login advertisement, at most
-- one more after first contact with the other peer (it may have missed
-- ours), then none for later requests in the interval.
do
 P.Boot({'Alpha','Bravo'},5)
 for _=1,400 do P.Step() end
 local function Count(code) local n=0;for _,t in ipairs(P.trace) do if t.from==P.A.name and t.code==code then n=n+1 end end;return n end
 local req0=Count('WLRQ')
 for _=1,2 do
  P.A.e.Nexus.Sync.RequestSync()
  P.Advance(40)
 end
 local caps1,req1=Count('WLCP'),Count('WLRQ')
 for _=1,3 do
  P.A.e.Nexus.Sync.RequestSync()
  P.Advance(40)
 end
 local req=Count('WLRQ')-req0
 check(req>=3 and Count('WLRQ')>req1,'fixture: several state requests went out within 300 s, some after first contact: '..req)
 check(caps1<=2 and Count('WLCP')==caps1,'at most one advertisement after first contact, then none within the interval: '..caps1..' then '..Count('WLCP')..' for '..Count('WLRQ')..' requests')
end

-- 7. The responder reloads after the requester's last advertisement: the
-- responder's capability table is empty, the requester's advertisement
-- interval has not passed. The restarted peer's own traffic makes the
-- requester state its capability again, so its next answer is full.
do
 P.Boot({'Alpha','Bravo'},5,nil,{slots={Slots('Alpha',MIXED),nil}})
 for _=1,400 do P.Step() end
 local function BravoCaps() local n=0;for _,t in ipairs(P.trace) do if t.from==P.B.name and t.code=='WLCP' then n=n+1 end end;return n end
 check(BravoCaps()>=1,'fixture: Bravo advertised at login')
 local before=BravoCaps()
 P.Rejoin(1) -- Alpha reloads: its capability table starts empty
 P.Advance(20)
 local id=Share(P.A,'Locked roles seven')
 P.Until(function() return P.Full(P.B,id) end)
 local got=Get(P.B,id)
 check(Key(got.lockedEchoes)==LOCKED and got.lockedAuthorityProven==true,'the answer after the reload carries the locked targets: '..Key(got.lockedEchoes))
 check(BravoCaps()>before,'Bravo stated its capability again after Alpha restarted')
end

print('PASS sync_locked_roles_wire checks='..checks)
