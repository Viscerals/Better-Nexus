-- Fail-closed guards of the explicit keep-current / preserve-legacy recovery
-- (control BN-CONTROL-LEGACY-RECOVERY-20261001-008): input drift, stale code,
-- values that cannot or may not be preserved, malformed / future / full /
-- conflicting preservation stores, fault injection with rollback, and a
-- simulated crash image. Every refusal changes nothing. Real TOC boot,
-- Store coordinator, lifecycle and commands; synthetic data only.
local S=dofile('tests/prototype/legacy_recovery_support.lua')
local F=S.F
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local STORE=S.STORE
local REAUTH='LEGACY_DISPOSITION_REAUTH_REQUIRED'

local function Offered(legacy,prepare)
 local db=S.Current()
 if prepare then prepare(db) end
 local H=S.Start(db,legacy)
 check(Nexus.StartupStatus().reason==REAUTH,'fixture: the refusal is reached')
 return H,S.Code(H)
end
-- A refused confirmation: the reason is named and nothing changes.
local function Refuses(H,code,reason,label)
 local before=F.Serialize(NexusDB);local global=WishlistRealizerDB
 local out=S.Plain(S.Say(H,'legacy keep '..tostring(code)))
 check(out:find(reason,1,true),label..': '..reason..': '..out)
 check(F.Serialize(NexusDB)==before and WishlistRealizerDB==global,label..': nothing changed')
end

-- 1. Input drift after the offer. Each is INPUT_DRIFT. An in-place edit of the
-- same legacy table may be reviewed again (a new offer, a new code); a
-- replaced table, root, bundle or receipt blocks a new offer until the player
-- reloads and reviews again.
do
 local H,code=Offered(S.Legacy())
 WishlistRealizerDB.extra=1
 Refuses(H,code,'INPUT_DRIFT','legacy edited in place')
 -- The player may review the edited value again: that is a new offer with a
 -- new code, and the old code is stale.
 local fresh=S.Code(H)
 check(fresh and fresh~=code,'drift: a new offer for the edited value has a new code')
 Refuses(H,code,'CODE_MISMATCH','old code after a new offer')
 local edited=F.Serialize(WishlistRealizerDB)
 S.Say(H,'legacy keep '..fresh)
 check(WishlistRealizerDB==nil,'drift: the new code confirms the edited value')
 check(F.Serialize(NexusDB[STORE].entries[S.Seam().Snapshot(assert(loadstring('return '..edited))()).digest].value)==edited,
  'drift: the preserved value is the edited value, in full')
 H,code=Offered(S.Legacy())
 WishlistRealizerDB=S.Legacy()
 Refuses(H,code,'INPUT_DRIFT','legacy replaced by an equal table')
 check(S.Plain(S.Say(H,'legacy')):find('INPUT_DRIFT',1,true),'drift: a new offer is blocked: legacy identity changed')
 H,code=Offered(S.Legacy())
 WishlistRealizerDB=nil
 Refuses(H,code,'INPUT_DRIFT','legacy global cleared')
 H,code=Offered(S.Legacy())
 NexusDB=S.Copy(NexusDB)
 Refuses(H,code,'INPUT_DRIFT','current root replaced by a copy')
 H,code=Offered(S.Legacy())
 NexusDB.authorityBundle=S.Copy(NexusDB.authorityBundle)
 Refuses(H,code,'INPUT_DRIFT','authority bundle replaced')
 H,code=Offered(S.Legacy())
 NexusDB.nexusStoreMigrations.wishlistRealizerDB={version=1,completed=true,decision='noLegacy'}
 Refuses(H,code,'INPUT_DRIFT','receipt replaced by an equal table')
 H,code=Offered(S.Legacy())
 NexusDB.nexusStoreMigrations.wishlistRealizerDB.decision='keptCurrent'
 Refuses(H,code,'INPUT_DRIFT','receipt decision changed')
end

-- 2. A correct code without an offer is refused; a stale code from another
-- value is refused.
do
 local legacy=S.Legacy()
 local H=S.Start(S.Current(),legacy)
 local right=S.Seam().Snapshot(legacy).digest:sub(1,12)
 Refuses(H,right,'NO_OFFER','correct code, no offer')
 local first=S.Code(H)
 check(first==right,'offer: the shown code is the first 12 digest characters')
 local stale=S.Seam().Snapshot(S.Legacy('B')).digest:sub(1,12)
 check(stale~=right,'fixture: another value has another code')
 Refuses(H,stale,'CODE_MISMATCH','stale code from another value')
 Refuses(H,right:upper():sub(1,6),'CODE_MISMATCH','short code')
 Refuses(H,'zzzzzzzzzzzz','CODE_MISMATCH','non-hex code')
end

-- 3. Values that cannot be preserved (LEGACY_NOT_PRESERVABLE) or exceed a
-- bound (PRESERVATION_CAPACITY): classified exactly, refused at the offer,
-- and a confirmation has no offer to stand on.
do
 local P
 local function Deep(n) local t={};local top=t;for i=2,n do local c={};t.c=c;t=c end return top end
 local cases={
  {'metatable',function() return setmetatable({a=1},{__index=function() end}) end,'LEGACY_NOT_PRESERVABLE','a table with a metatable'},
  {'function value',function() return {a=function() end} end,'LEGACY_NOT_PRESERVABLE','a value of type function'},
  {'cycle',function() local t={a=1};t.self=t;return t end,'LEGACY_NOT_PRESERVABLE','appears twice'},
  {'shared table',function() local x={1};return {a=x,b=x} end,'LEGACY_NOT_PRESERVABLE','appears twice'},
  {'NaN',function() return {a=0/0} end,'LEGACY_NOT_PRESERVABLE','not finite'},
  {'infinity',function() return {a=1/0} end,'LEGACY_NOT_PRESERVABLE','not finite'},
  {'table key',function() return {[{}]=1} end,'LEGACY_NOT_PRESERVABLE','a key of type table'},
  {'nested metatable',function() return {a=setmetatable({},{})} end,'LEGACY_NOT_PRESERVABLE','a table with a metatable'},
  {'text instead of a table',function() return 'text' end,'LEGACY_NOT_PRESERVABLE','not a table'},
  {'depth 17',function() return Deep(17) end,'PRESERVATION_CAPACITY','more than 16 levels'},
  {'string 16385 bytes',function() return {a=('x'):rep(16385)} end,'PRESERVATION_CAPACITY','a string over 16384 bytes'},
  {'key 257 bytes',function() return {[('k'):rep(257)]=1} end,'PRESERVATION_CAPACITY','a key over 256 bytes'},
  {'65537 tables',function() local t={};for i=1,65536 do t[i]={} end return t end,'PRESERVATION_CAPACITY','more than 65536 tables'},
  {'over 4 MiB',function() local t={};for i=1,300 do t['k'..i]=('v'):rep(16000) end return t end,'PRESERVATION_CAPACITY','more than 4194304 bytes in all'},
  {'524289 entries',function() local t={};for i=1,524289 do t[i]=true end return t end,'PRESERVATION_CAPACITY','more than 524288 entries'},
 }
 for _,case in ipairs(cases) do
  local legacy=case[2]()
  local H=S.Start(S.Current(),legacy)
  P=S.Seam()
  check(Nexus.StartupStatus().reason==REAUTH and Nexus.StartupStatus().failure.legacyClass=='FOREIGN_BLOCK',
   case[1]..': refused as FOREIGN_BLOCK as before')
  local snapshot,why,detail=P.Snapshot(legacy)
  check(snapshot==nil and why==case[3],case[1]..': classified '..case[3]..' (got '..tostring(why)..')')
  check(type(detail)=='string' and detail:find(case[4],1,true),case[1]..': the detail names what was hit: '..tostring(detail))
  local before=F.Serialize(NexusDB)
  local out=S.Plain(S.Say(H,'legacy'))
  check(out:find(case[3],1,true) and out:find('Nothing was changed',1,true),case[1]..': the offer is blocked: '..out)
  check(out:find(case[4],1,true),case[1]..': the answer names the bound or the value: '..out)
  check(not out:find('/nexus legacy keep',1,true),case[1]..': no confirmation command is offered')
  Refuses(H,'000000000000','NO_OFFER',case[1])
  check(F.Serialize(NexusDB)==before and WishlistRealizerDB==legacy,case[1]..': legacy and current unchanged')
 end
 -- At the bounds the value is accepted.
 local ok=S.Seam()
 check(ok.Snapshot(Deep(16)),'bound: depth 16 is accepted')
 check(ok.Snapshot({a=('x'):rep(16384)}),'bound: string 16384 bytes is accepted')
 check(ok.Snapshot({[('k'):rep(256)]=1}),'bound: key 256 bytes is accepted')
 local t={};for i=1,65535 do t[i]={} end
 check(ok.Snapshot(t),'bound: 65536 tables including the root are accepted')
 check(ok.Snapshot({[true]=1,[false]=2,[1.5]=3,[-2]=4,a={}}),'bound: boolean and number keys are accepted')
 -- The digest does not depend on insertion order, and changes with the value.
 local x,y={},{}
 x.a,x.b,x.c=1,2,3;y.c,y.b,y.a=3,2,1
 check(ok.Snapshot(x).digest==ok.Snapshot(y).digest and #ok.Snapshot(x).digest==16,'digest: independent of insertion order')
 y.a=9
 check(ok.Snapshot(x).digest~=ok.Snapshot(y).digest,'digest: changes with the value')
 check(ok.Snapshot({a='1'}).digest~=ok.Snapshot({a=1}).digest,'digest: a string is not a number')
end

-- 4. The preservation store: malformed, future, full, conflicting, reused.
do
 local function Blocked(label,reason,prepare)
  local legacy=S.Legacy()
  local db=S.Current();prepare(db)
  local H=S.Start(db,legacy)
  local before=F.Serialize(NexusDB)
  local out=S.Plain(S.Say(H,'legacy'))
  check(out:find(reason,1,true) and not out:find('/nexus legacy keep',1,true),label..': offer blocked '..reason..': '..out)
  check(F.Serialize(NexusDB)==before and WishlistRealizerDB==legacy,label..': nothing changed')
 end
 local _,valid=S.Entry(S.Legacy('Z'))
 local function WithStore(entries) return {version=1,entries=entries} end
 Blocked('store is a number','ARCHIVE_MALFORMED',function(db) db[STORE]=5 end)
 Blocked('store without version','ARCHIVE_MALFORMED',function(db) db[STORE]={entries={}} end)
 Blocked('store future version','ARCHIVE_FUTURE',function(db) db[STORE]={version=2,entries={}} end)
 Blocked('store unknown key','ARCHIVE_MALFORMED',function(db) db[STORE]={version=1,entries={},extra=1} end)
 Blocked('entries not a table','ARCHIVE_MALFORMED',function(db) db[STORE]={version=1,entries=3} end)
 Blocked('store metatable','ARCHIVE_MALFORMED',function(db) db[STORE]=setmetatable({version=1,entries={}},{}) end)
 Blocked('entry key not a digest','ARCHIVE_MALFORMED',function(db) db[STORE]=WithStore({short=S.Copy(valid)}) end)
 Blocked('entry digest differs from its key','ARCHIVE_MALFORMED',function(db)
  local e=S.Copy(valid);e.digest='0000000000000000';db[STORE]=WithStore({[valid.digest]=e}) end)
 Blocked('entry unknown field','ARCHIVE_MALFORMED',function(db)
  local e=S.Copy(valid);e.extra=1;db[STORE]=WithStore({[valid.digest]=e}) end)
 Blocked('entry value not a table','ARCHIVE_MALFORMED',function(db)
  local e=S.Copy(valid);e.value='x';db[STORE]=WithStore({[valid.digest]=e}) end)
 -- Four other entries fill the store.
 Blocked('store full','PRESERVATION_CAPACITY',function(db)
  local entries={}
  for _,tag in ipairs({'1','2','3','4'}) do local d,e=S.Entry(S.Legacy(tag));entries[d]=e end
  db[STORE]=WithStore(entries) end)
 -- Same digest, different value: a conflict, never an overwrite.
 do
  local legacy=S.Legacy()
  local digest,entry=S.Entry(legacy)
  entry.value.customLegacy.keep='tampered'
  local db=S.Current();db[STORE]=WithStore({[digest]=entry})
  local H=S.Start(db,legacy)
  local tamperedText=F.Serialize(NexusDB[STORE])
  check(S.Plain(S.Say(H,'legacy')):find('ARCHIVE_CONFLICT',1,true),'conflict: the offer is blocked')
  check(F.Serialize(NexusDB[STORE])==tamperedText and WishlistRealizerDB==legacy,'conflict: the existing entry is not overwritten and the legacy stays')
 end
 -- The store changes after the offer: re-inspected at confirmation.
 do
  local legacy=S.Legacy()
  local H,code=Offered(legacy)
  NexusDB[STORE]={version=1,entries={},unknown=true}
  Refuses(H,code,'ARCHIVE_MALFORMED','store corrupted after the offer')
  H,code=Offered(legacy)
  NexusDB[STORE]={version=3,entries={}}
  Refuses(H,code,'ARCHIVE_FUTURE','store made future after the offer')
  H,code=Offered(legacy)
  local entries={}
  for _,tag in ipairs({'1','2','3','4'}) do local d,e=S.Entry(S.Legacy(tag));entries[d]=e end
  NexusDB[STORE]=WithStore(entries)
  Refuses(H,code,'PRESERVATION_CAPACITY','store filled after the offer')
  H,code=Offered(legacy)
  local digest,entry=S.Entry(legacy);entry.value.flag='changed'
  NexusDB[STORE]=WithStore({[digest]=entry})
  Refuses(H,code,'ARCHIVE_CONFLICT','conflicting entry added after the offer')
 end
 -- An equal entry left by an interrupted earlier run is reused, not duplicated.
 do
  local legacy=S.Legacy()
  local digest,entry=S.Entry(legacy)
  local db=S.Current();db[STORE]=WithStore({[digest]=entry})
  local H=S.Start(db,legacy)
  local entryRef=NexusDB[STORE].entries[digest];local text=F.Serialize(entryRef)
  local code=S.Code(H)
  local out=S.Plain(S.Say(H,'legacy keep '..code))
  check(WishlistRealizerDB==nil and out:find('preserved',1,true),'reuse: an equal existing entry completes the recovery: '..out)
  check(#S.Entries(NexusDB)==1 and NexusDB[STORE].entries[digest]==entryRef and F.Serialize(entryRef)==text,
   'reuse: the existing entry is the same table, unchanged, and not duplicated')
 end
 -- Another value's entry coexists and is left byte-identical.
 do
  local other=S.Legacy('Other')
  local odigest,oentry=S.Entry(other)
  local db=S.Current();db[STORE]=WithStore({[odigest]=oentry})
  local H=S.Start(db,S.Legacy())
  local otherText=F.Serialize(NexusDB[STORE].entries[odigest])
  local code=S.Code(H)
  S.Say(H,'legacy keep '..code)
  check(WishlistRealizerDB==nil and #S.Entries(NexusDB)==2,'coexist: a second entry is added')
  check(F.Serialize(NexusDB[STORE].entries[odigest])==otherText,'coexist: the older entry is byte-identical')
 end
end

-- 5. Fault injection: every failure after the offer rolls back what the call
-- added, leaves the legacy global in place, and a retry succeeds.
do
 local function Case(label,reason,inject,preexisting)
  local legacy=S.Legacy()
  local db=S.Current()
  local oid,oentry
  if preexisting then oid,oentry=S.Entry(S.Legacy('Other'));db[STORE]={version=1,entries={[oid]=oentry}} end
  local H=S.Start(db,legacy)
  local code=S.Code(H)
  local P=S.Seam()
  local saved={Attach=P.Attach,Dispose=P.Dispose,Bound=P.Bound}
  local before=F.Serialize(NexusDB)
  local restore=inject(P,saved)
  local out=S.Plain(S.Say(H,'legacy keep '..code))
  for key,fn in pairs(saved) do P[key]=fn end
  check(out:find(reason,1,true),label..': '..reason..': '..out)
  check(WishlistRealizerDB==legacy,label..': the legacy global is back, the same table')
  check(F.Serialize(NexusDB)==before,label..': the current root is exactly as before (nothing added)')
  check(F.Serialize(legacy)==F.Serialize(S.Legacy()),label..': the legacy table is unmodified')
  -- Retry without the fault.
  out=S.Plain(S.Say(H,'legacy keep '..code))
  check(WishlistRealizerDB==nil and out:find('preserved',1,true),label..': a retry succeeds: '..out)
  check(F.Serialize(NexusDB[STORE].entries[S.Seam().Snapshot(S.Legacy()).digest].value)==F.Serialize(S.Legacy()),label..': the retry preserves the full value')
  if preexisting then check(F.Serialize(NexusDB[STORE].entries[oid])==F.Serialize(oentry),label..': the other entry is untouched') end
 end
 for _,preexisting in ipairs({false,true}) do
  local suffix=preexisting and ' (store already holds another entry)' or ''
  Case('attach raises'..suffix,'PRESERVATION_FAILED',function(P,saved)
   P.Attach=function() error('injected attach failure') end end,preexisting)
  Case('attach adds then raises'..suffix,'PRESERVATION_FAILED',function(P,saved)
   P.Attach=function(...) saved.Attach(...);error('injected after attach') end end,preexisting)
  Case('attach refuses'..suffix,'ARCHIVE_CONFLICT',function(P,saved)
   P.Attach=function() return false,'ARCHIVE_CONFLICT' end end,preexisting)
  Case('inputs drift after attach'..suffix,'INPUT_DRIFT',function(P,saved)
   local calls=0
   P.Bound=function(C) calls=calls+1;local b=saved.Bound(C);if calls>=2 then b.decision='drifted' end return b end end,preexisting)
  Case('dispose does not clear'..suffix,'DISPOSITION_FAILED',function(P,saved)
   P.Dispose=function() return false end end,preexisting)
  Case('dispose clears then raises'..suffix,'PRESERVATION_FAILED',function(P,saved)
   P.Dispose=function(legacy) WishlistRealizerDB=nil;error('injected after dispose') end end,preexisting)
 end
end

-- 5b. The two lowest-level invariants, exercised on the real functions.
-- Attach never overwrites an existing entry, whatever the caller checked.
do
 local H=S.Start(S.Current(),S.Legacy())
 local P=S.Seam()
 local snapshot=assert(P.Snapshot(S.Legacy()))
 local _,existing=S.Entry(S.Legacy())
 existing.value.flag='kept'
 NexusDB[STORE]={version=1,entries={[snapshot.digest]=existing}}
 local text=F.Serialize(NexusDB[STORE])
 local undo={}
 local ok,why=P.Attach(NexusDB,snapshot,undo)
 check(ok==false and why=='ARCHIVE_CONFLICT','attach: an existing entry is refused, never overwritten: '..tostring(why))
 check(F.Serialize(NexusDB[STORE])==text and next(undo)==nil,'attach: the store is byte-identical and nothing is queued for rollback')
end
-- The real verified nil write: a global that ignores the write is a
-- DISPOSITION_FAILED, the entry is rolled back and the legacy stays.
do
 local legacy=S.Legacy()
 local H=S.Start(S.Current(),legacy)
 local code=S.Code(H)
 local held=WishlistRealizerDB
 local previous=getmetatable(_G)
 rawset(_G,'WishlistRealizerDB',nil)
 setmetatable(_G,{__index=function(_,key) if key=='WishlistRealizerDB' then return held end end,
  __newindex=function(table,key,value) if key~='WishlistRealizerDB' then rawset(table,key,value) end end})
 local before=F.Serialize(NexusDB)
 local out=S.Plain(S.Say(H,'legacy keep '..code))
 setmetatable(_G,previous)
 rawset(_G,'WishlistRealizerDB',held)
 check(out:find('DISPOSITION_FAILED',1,true),'dispose: a write that does not take is DISPOSITION_FAILED: '..out)
 check(F.Serialize(NexusDB)==before and WishlistRealizerDB==held and held==legacy,'dispose: the entry is rolled back and the legacy is intact')
 out=S.Plain(S.Say(H,'legacy keep '..code))
 check(WishlistRealizerDB==nil and out:find('preserved',1,true),'dispose: a retry with a working global succeeds: '..out)
end

-- 5c. "Never release without a verified full copy" is pinned directly.
do
 -- A copy that silently lost a key (Attach stores it and reports success) is
 -- caught by the verification: PRESERVATION_FAILED, the legacy stays.
 local legacy=S.Legacy()
 local H=S.Start(S.Current(),legacy)
 local code=S.Code(H)
 local P=S.Seam();local real=P.Attach
 P.Attach=function(db,snapshot,undo)
  snapshot.copy.customLegacy.keep=nil
  return real(db,snapshot,undo)
 end
 local before=F.Serialize(NexusDB)
 local out=S.Plain(S.Say(H,'legacy keep '..code))
 P.Attach=real
 check(out:find('PRESERVATION_FAILED',1,true),'copy lost a key: caught: '..out)
 check(WishlistRealizerDB==legacy and F.Serialize(NexusDB)==before,'copy lost a key: the legacy stays and nothing was added')
 -- A copy that gained a key is caught the same way (the comparison is two-way).
 P.Attach=function(db,snapshot,undo)
  snapshot.copy.extraKey='added'
  return real(db,snapshot,undo)
 end
 out=S.Plain(S.Say(H,'legacy keep '..code))
 P.Attach=real
 check(out:find('PRESERVATION_FAILED',1,true) and WishlistRealizerDB==legacy and F.Serialize(NexusDB)==before,'copy gained a key: caught')
 -- A same-digest entry that is a strict subset of the legacy value is a conflict.
 local digest,entry=S.Entry(S.Legacy())
 entry.value.flag=nil
 local db=S.Current();db[STORE]={version=1,entries={[digest]=entry}}
 local H2=S.Start(db,S.Legacy())
 check(S.Plain(S.Say(H2,'legacy')):find('ARCHIVE_CONFLICT',1,true),'subset entry: a conflict, never reused')
 -- ... and so is one that has an extra key.
 digest,entry=S.Entry(S.Legacy());entry.value.extraKey=1
 db=S.Current();db[STORE]={version=1,entries={[digest]=entry}}
 H2=S.Start(db,S.Legacy())
 check(S.Plain(S.Say(H2,'legacy')):find('ARCHIVE_CONFLICT',1,true),'superset entry: a conflict, never reused')
 -- Numbers and booleans survive exactly (a float, a large value, a negative zero).
 local H3=S.Start(S.Current(),S.Legacy())
 S.Say(H3,'legacy keep '..S.Code(H3))
 local saved=NexusDB[STORE].entries[S.Seam().Snapshot(S.Legacy()).digest].value
 check(saved.float==0.1+0.2 and saved.huge==1e300 and saved.yes==true and 1/saved.negzero==-math.huge,
  'values: float, large number, true and negative zero are preserved exactly')
end

-- 5d. Double fault: Dispose clears the global, raises, and the global then
-- refuses the restore. The verified copy is KEPT (nothing is lost) and the
-- reason says the older copy could not be put back.
do
 local legacy=S.Legacy()
 local H=S.Start(S.Current(),legacy)
 local code=S.Code(H)
 local held=WishlistRealizerDB
 local P=S.Seam();local real=P.Dispose
 local previous=getmetatable(_G)
 local cleared=false
 rawset(_G,'WishlistRealizerDB',nil)
 setmetatable(_G,{__index=function(_,key) if key=='WishlistRealizerDB' and not cleared then return held end end,
  __newindex=function(table,key,value)
   if key=='WishlistRealizerDB' then if value==nil then cleared=true end else rawset(table,key,value) end
  end})
 P.Dispose=function() WishlistRealizerDB=nil;error('injected after dispose') end
 local out=S.Plain(S.Say(H,'legacy keep '..code))
 P.Dispose=real
 setmetatable(_G,previous)
 rawset(_G,'WishlistRealizerDB',nil)
 check(out:find('ROLLBACK_INCOMPLETE',1,true) and out:find('nothing is lost',1,true),'double fault: named, and nothing is lost: '..out)
 local entry=NexusDB[STORE] and NexusDB[STORE].entries[P.Snapshot(S.Legacy()).digest]
 check(entry and F.Serialize(entry.value)==F.Serialize(S.Legacy()),'double fault: the complete copy is kept in the archive')
end

-- 5e. A receipt from a newer build, or a malformed one, fails closed.
do
 for _,case in ipairs({{'future','RECEIPT_FUTURE',{version=2,completed=true,decision='noLegacy'}},
   {'malformed','RECEIPT_MALFORMED',{version=1,completed='yes'}}}) do
  local legacy=S.Legacy()
  local db=S.Current();db.nexusStoreMigrations.wishlistRealizerDB=case[3]
  local H=S.Start(db,legacy)
  check(Nexus.StartupStatus().reason==REAUTH,case[1]..' receipt: refused as before')
  local before=F.Serialize(NexusDB)
  local out=S.Plain(S.Say(H,'legacy'))
  check(out:find(case[2],1,true) and not out:find('/nexus legacy keep',1,true),case[1]..' receipt: the offer is blocked: '..out)
  Refuses(H,'000000000000','NO_OFFER',case[1]..' receipt')
  check(F.Serialize(NexusDB)==before and WishlistRealizerDB==legacy,case[1]..' receipt: nothing changed')
 end
end

-- 5f. An error inside the coordinator is recorded, not swallowed, and the
-- command reports a refusal.
do
 local H=S.Start(S.Current(),S.Legacy())
 local P=S.Seam();local real=P.Offer
 P.Offer=function() error('injected recovery error') end
 local before=Nexus.Errors.SessionCount()
 local out=S.Plain(S.Say(H,'legacy'))
 P.Offer=real
 check(out:find('PRESERVATION_FAILED',1,true),'error: the command reports a refusal: '..out)
 check(Nexus.Errors.SessionCount()==before+1 and tostring(Nexus.lastError):find('injected recovery error',1,true),
  'error: the failure is recorded: '..tostring(Nexus.lastError))
end

-- 6. A crash image: the process stops after the entry is attached and before
-- the legacy global is released. The saved file then holds both. The next
-- start-up refuses again and the same recovery completes without a duplicate.
do
 local legacy=S.Legacy()
 local H=S.Start(S.Current(),legacy)
 local code=S.Code(H)
 local P=S.Seam();local real=P.Dispose
 local image,legacyImage
 P.Dispose=function(value)
  image=F.Serialize(NexusDB);legacyImage=F.Serialize(WishlistRealizerDB)
  error('simulated crash after attach')
 end
 S.Say(H,'legacy keep '..code)
 P.Dispose=real
 check(image and image:find(STORE,1,true) and legacyImage==F.Serialize(S.Legacy()),'crash image: entry attached, legacy still present')
 local H2=S.Start(assert(loadstring('return '..image))(),assert(loadstring('return '..legacyImage))())
 check(Nexus.StartupStatus().reason==REAUTH,'crash image: the same refusal returns')
 local again=S.Code(H2)
 check(again==code,'crash image: the same code')
 S.Say(H2,'legacy keep '..again)
 check(WishlistRealizerDB==nil and #S.Entries(NexusDB)==1,'crash image: the recovery completes with one entry')
 check(F.Serialize(NexusDB[STORE].entries[P.Snapshot(S.Legacy()).digest].value)==F.Serialize(S.Legacy()),'crash image: the preserved value is complete')
end

-- 7. After success the session is not resumed: start-up stays stopped until
-- the player reloads, and nothing writes the current data meanwhile.
do
 local H=S.Start(S.Current(),S.Legacy())
 local code=S.Code(H)
 S.Say(H,'legacy keep '..code)
 local saved=F.Serialize(NexusDB)
 H.Advance(10,.05)
 local s=Nexus.StartupStatus()
 check(s.state=='failed' and not s.coreReady and s.reason==REAUTH,'after success: the session stays stopped until reload')
 check(Nexus.Store.StateWriteStatus().mode~='durable','after success: no durable write eligibility')
 check(F.Serialize(NexusDB)==saved,'after success: nothing writes the current data before the reload')
 check(S.Plain(S.Say(H,'status')):find('Startup stopped: '..REAUTH,1,true),'after success: status states the stopped start-up')
end

print('PASS legacy_recovery_guards: drift, stale code, non-preservable and over-limit values, store states, rollback under injected faults, crash image, no resume checks='..checks)
