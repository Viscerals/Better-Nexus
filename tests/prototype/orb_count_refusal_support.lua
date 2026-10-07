-- Shared definitions of the Orb count-refusal regressions: orb_count_refusal_truthful
-- (the refusal text) and orb_count_refusal_fallbacks (the honest fallbacks).
-- The trust-gate guards of locked_shape_capture (C4), locked_shape_correlation
-- (Q7, Q8) and orb_passive_readiness_report (R7) read R.TrustRefusal from here,
-- so they keep guarding the gate (the refusal and its stage) without pinning
-- the old text of the over-cap case. Not a test itself: the name ends in
-- _support, so tools/ci_check.py does not list it. Loading it reads and changes
-- nothing; R.Fixture and R.Spies act only on the harness a test passes in.
local R={}

-- The shared text of the OrbAdapter.Read trust gate at b704660
-- (core/OrbAdapter.lua). It stays the honest answer of every trust refusal
-- except the one the count-refusal tests are about.
R.FALLBACK='Waiting for current rolled and locked Echo data from the server.'
-- Wording that presents a refusal as an unanswered or late server reply.
R.WAITING={'wait','loading','not yet','pending','once it is available','no reply','no response',
 'not answered','not received'}
-- Words that name the refused data or its count.
R.NAMED={'count','cop','data','limit','exceed','more than','above','too many'}

-- Is `text` a truthful count refusal? Nexus says that it rejected (or refused)
-- the locked Echo data or its count, in one bounded line, without wording that
-- reads as an awaited server reply. Returns true, or false and the first rule
-- the text does not meet. The rules fix what the text must say, not its words.
function R.Truthful(text)
 if type(text)~='string' then return false,'no text' end
 if text==R.FALLBACK then return false,'the shared server-data wait' end
 if text=='' or #text>240 or text:find('%c') then return false,'not one bounded line' end
 local l=text:lower()
 for _,w in ipairs(R.WAITING) do
  if l:find(w,1,true) then return false,'reads as an awaited server reply ('..w..')' end
 end
 if not l:find('nexus',1,true) then return false,'does not say that Nexus decided' end
 if not (l:find('reject',1,true) or l:find('refus',1,true)) then return false,'does not say rejected' end
 if not l:find('%f[%a]lock') then return false,'does not name the locked Echo data' end
 for _,w in ipairs(R.NAMED) do
  if l:find(w,1,true) then return true end
 end
 return false,'does not name the data or its count'
end
-- One of the two honest trust-gate texts: the shared wait, or a truthful count
-- refusal. For the guards that check the gate, not its wording.
function R.TrustRefusal(text)
 return text==R.FALLBACK or R.Truthful(text)==true
end

local function printable(v)
 local ok,s=pcall(tostring,v)
 return ok and type(s)=='string' and s or '<unprintable '..type(v)..'>'
end
R.printable=printable

-- Every check is evaluated and reported; finish() fails at the end if any did
-- not hold. SETUP: the fixture reached its state. EXPECT: healthy behaviour
-- that does not hold at b704660. GUARD: behaviour that already holds at
-- b704660 and must keep holding.
function R.Checker(name,realPcall)
 realPcall=realPcall or pcall
 local C={failures={},n={setup=0,expect=0,guard=0},bad={setup=0,expect=0,guard=0},raised=0}
 local function check(kind,ok,label,detail)
  C.n[kind]=C.n[kind]+1
  if ok then return true end
  C.bad[kind]=C.bad[kind]+1
  local line=kind:upper()..' '..label..(detail~=nil and (' ['..printable(detail)..']') or '')
  C.failures[#C.failures+1]=line
  print('FAIL '..line)
  return false
 end
 function C.setup(ok,label,detail) return check('setup',ok and true or false,label,detail) end
 function C.expect(ok,label,detail) return check('expect',ok and true or false,label,detail) end
 function C.guard(ok,label,detail) return check('guard',ok and true or false,label,detail) end
 function C.scenario(label,fn)
  local ok,err=realPcall(fn)
  if not ok then
   C.raised=C.raised+1
   local line='RAISED '..label..': '..printable(err)
   C.failures[#C.failures+1]=line
   print('FAIL '..line)
  end
 end
 function C.finish(note)
  print(string.format('SUMMARY %s: expectations held %d of %d; guards held %d of %d; setup held %d of %d; scenarios raised %d',
   name,C.n.expect-C.bad.expect,C.n.expect,C.n.guard-C.bad.guard,C.n.guard,C.n.setup-C.bad.setup,C.n.setup,C.raised))
  if #C.failures>0 then
   error(name..': '..#C.failures..' check(s) failed ('..C.bad.expect..' expectation, '..C.bad.guard..' guard, '
    ..C.bad.setup..' setup, '..C.raised..' raised); first: '..C.failures[1],0)
  end
  print('PASS '..name..(note and (' '..note) or '')..' checks='..(C.n.setup+C.n.expect+C.n.guard))
 end
 return C
end

-- The fixture both tests share, on a booted orbs_support harness H and the
-- locked_shape_support helpers T. Artificial IDs and names only.
function R.Fixture(H,T)
 local A,O=H.A,H.O
 local X={PLAN='ZQ plan alpha',BASE_GRANTED=H.Clone(H.granted)}
 -- Five native-shaped locked records: GetLockedPerks keys one array per Echo
 -- name (as in orb_stacked_copies); each record is {spellId, quality, stacks}.
 X.HELD={{410003,0},{410004,3},{410005,0},{410006,3},{410007,2}}
 X.OVER={1,1,1,3,1}   -- seven held copies: one more than the six-copy cap
 X.AT_CAP={1,1,1,2,1} -- six held copies: the cap itself
 function X.Records(copies)
  local t={}
  for i,r in ipairs(X.HELD) do t[H.names[r[1]]]={{spellId=r[1],quality=r[2],stacks=copies[i]}} end
  return t
 end
 function X.Over() return X.Records(X.OVER) end
 function X.AtCap() return X.Records(X.AT_CAP) end
 -- The same native shape within the cap, with one record whose ID is invalid.
 function X.Invalid()
  local t=X.AtCap()
  t[H.names[410004]]={{spellId='ZQ_bad'}}
  return t
 end
 function X.Want(copies)
  local m={}
  for i,r in ipairs(X.HELD) do m[r[1]]=copies[i] end
  return m
 end
 function X.Trusted()
  H.holdGrantedResponse=nil;O.known=true;H.playerLevel=40
  H.granted=H.Clone(X.BASE_GRANTED);A.Owned()
  H.locked={};A.LockedOwned()
 end
 -- An active populated Saved Build whose Wishlist resolves through its
 -- association, so that the Orb read reaches its trust gate (as in
 -- locked_shape_correlation).
 function X.Assign()
  H.perks.serverBuildSlots={[1]={name='ZQ build one',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}}}
  H.perks.serverActiveSlot=1;H.Notify();A.Poll()
  return A.SetLoadoutWishlistIdentity(1,X.PLAN,{{spellId=410002,quality=2,stacks=1}})
 end
 -- The real Orb read: ok, snapshot, refusal text, stage.
 function X.Read() return T.realPcall(A.Orbs.Read) end
 -- One normal Orb window read (open, refresh, close): the snapshot and what the
 -- window showed, or nil and the error.
 function X.Window()
  local ok,snap,shown=T.realPcall(function()
   Nexus.OrbPanel.Show()
   local f=NexusOrbPanel
   local out={status=f.status:GetText(),targets=f.targets:GetText(),start=f.start:IsEnabled()}
   local s=f.snapshot
   f:Hide()
   return s,out
  end)
  if not ok then return nil,{error=printable(snap)} end
  return snap,shown
 end
 return X
end

-- Pass-through call counters on every game service member and on the adapter,
-- Orb adapter, Orb runtime and Store entries that read the game, request, send,
-- act or write. Behaviour is unchanged; restore() puts every original back.
-- work(fn) runs fn once with counting on and returns its results, the calls,
-- and whether anything was sent, acted on or saved.
function R.Spies(H,T)
 local A,M=H.A,H.M
 local S={on=false,calls={},saved={}}
 local function wrap(owner,name,label)
  if type(owner)~='table' or type(owner[name])~='function' then return end
  local fn=owner[name]
  S.saved[#S.saved+1]={owner,name,fn}
  owner[name]=function(...)
   if S.on then S.calls[label]=(S.calls[label] or 0)+1 end
   return fn(...)
  end
 end
 local function wrapAll(owner,prefix)
  if type(owner)~='table' then return end
  local names={}
  for k,v in pairs(owner) do if type(v)=='function' then names[#names+1]=k end end
  table.sort(names)
  for _,k in ipairs(names) do wrap(owner,k,prefix..k) end
 end
 wrapAll(ProjectEbonhold.PerkService,'PerkService.')
 wrapAll(ProjectEbonhold.OrbService,'OrbService.')
 wrap(ProjectEbonhold.PlayerRunService,'GetCurrentData','PlayerRunService.GetCurrentData')
 wrap(ProjectEbonholdOptionsService,'GetSetting','Options.GetSetting')
 wrap(ProjectEbonholdOptionsService,'SetSetting','Options.SetSetting')
 for _,k in ipairs({'Owned','LockedOwned','RequestGranted','RequestSlots','DumpLockedPerksRaw','MaxPermanentEchoes',
  'UnlockedSlots','LockPerk','UnlockPerk','Take','Banish','Reroll','Freeze','Activate','Save','UploadWishlist',
  'ToggleLever','SetSoloPicker','RestoreAutoAccept','Poll','RunBoundaryReset','EchoActiveSlotGeneration',
  'Board','Charges','Slots','Wishlist'}) do
  wrap(A,k,'GameAdapter.'..k)
 end
 for _,k in ipairs({'Read','Balance','ServiceState','RequestRefresh','CaptureStart','TransportStart','Watch',
  'Unwatch','Acquire','Rebind','Spend','Select','Release'}) do
  wrap(A.Orbs,k,'Orbs.'..k)
 end
 for _,k in ipairs({'Status','Recheck','Pump','Start','Prepare','Confirm','Resume','Pause','Stop',
  'UseAssignedWishlist'}) do
  wrap(M,k,'OrbRuntime.'..k)
 end
 local internals=Nexus.MainInternals
 wrap(type(internals)=='table' and internals.StoreAuthorityOwner or nil,'UpdateStateV1','Store.UpdateStateV1')
 local realSpellInfo=GetSpellInfo
 GetSpellInfo=function(...)
  if S.on then S.calls.GetSpellInfo=(S.calls.GetSpellInfo or 0)+1 end
  return realSpellInfo(...)
 end
 function S.work(fn,...)
  local sent,actions,db=#H.sent,#H.actions,T.serialize(NexusDB)
  S.calls={};S.on=true
  local out={T.realPcall(fn,...)}
  S.on=false
  return {ok=out[1],a=out[2],b=out[3],c=out[4],calls=S.calls,sent=#H.sent-sent,
   actions=#H.actions-actions,saved=T.serialize(NexusDB)~=db}
 end
 function S.restore()
  for i=#S.saved,1,-1 do
   local s=S.saved[i]
   s[1][s[2]]=s[3]
  end
  S.saved={}
  GetSpellInfo=realSpellInfo
 end
 return S
end
function R.SameCalls(a,b)
 for k,n in pairs(a or {}) do if (b or {})[k]~=n then return false end end
 for k,n in pairs(b or {}) do if (a or {})[k]~=n then return false end end
 return true
end
function R.CallList(calls)
 local out={}
 for k,n in pairs(calls or {}) do out[#out+1]=k..' x'..n end
 table.sort(out)
 return table.concat(out,', ')
end
-- The counters and revisions (locked_shape_support T.counters) that moved.
function R.Moved(a,b)
 local moved={}
 for k,v in pairs(a or {}) do if (b or {})[k]~=v then moved[#moved+1]=k..' '..printable(v)..'->'..printable((b or {})[k]) end end
 for k,v in pairs(b or {}) do if (a or {})[k]==nil and v~=nil then moved[#moved+1]=k..' nil->'..printable(v) end end
 table.sort(moved)
 return moved
end

return R
