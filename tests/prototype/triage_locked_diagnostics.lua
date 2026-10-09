-- Issue #29 triage: the passive Locked Echoes diagnostics describe the current
-- locked-Echo contract truthfully, and reading them never acts.
-- Current contract (source at 8eb6a3a): GameAdapter.LockPerk/UnlockPerk exist
-- (core/GameAdapter.lua 4305-4337); their only caller is the optional slot
-- automation (core/AutomationRuntime.lua TryAutoLock), behind Automation ON,
-- the separate autoLockEchoes option (off by default), trusted locked state,
-- a known capacity and its attempt lifecycle. The diagnostics owner gets a
-- read-only adapter facade (core/Main.lua 703-716). The Slot actions trace
-- already reports "locked records: occupied/capacity" (AutomationRuntime.lua
-- 1901-1903); the Locked Echoes header sums held copies over a fixed six
-- (core/MainDiagnostics.lua 492-497) and ignores whether the read is trusted.
-- Native contract (static export text, never executed): one locked record per
-- permanent slot keeps its whole stack (perks_service.lua 308-315); the
-- capacity is GetMaximumPermanentEchoes, 0 until a positive SS18 header
-- (perks_service.lua 16, 276-281, 741-743); the journal admits a lock while
-- #lockedPerks < capacity (echo_journal.lua 4532-4539); the HUD draws one disc
-- per capacity slot and one record per disc with its stack badge
-- (player_run_ui.lua 1450-1485, 1560-1573); the journal's six discs are
-- display only (echo_journal.lua 3233-3236). No server rule is claimed.
-- EXPECT (fails at 8eb6a3a), the Locked Echoes page:
--   R1 five records holding 1,1,1,3,1 at capacity 6: 5/6 occupied records,
--      never 7/6, and the seven held copies stated as copies;
--   C1 the occupied records and capacity the Slot actions trace reports;
--   M1 seven records at capacity 7: 7/7, no /6 maximum;
--   M2 three records holding four copies, capacity unknown (getter 0): the
--      capacity named unknown, 3 counted, no /6 maximum;
--   M3 a refused read (seven records at capacity 6) and M4 an unreadable one:
--      named not trusted or unavailable, with no Wishlist comparison drawn
--      from it (at 8eb6a3a M4 reads 0/6 and "Every currently locked Echo ID
--      appears in this Wishlist").
-- GUARD (holds at 8eb6a3a): no page claims Nexus cannot lock or unlock; the
-- header says display only and names the optional automation. Disabled: the
-- trace and the Status page say the option is off, the history is empty, no
-- write. Enabled with every gate open, reading writes nothing; one automation
-- step submits one lock, held as awaiting-confirmation in the trace, recorded
-- as an attempt, not shown as locked. Refused: one refused service call, its
-- error recorded, retained as rejected, not retried, not shown as locked.
-- Full occupancy without a designed replacement: nothing destructive was
-- attempted and the page changes nothing. Single-copy records agree with the
-- trace; no records at capacity 6 read 0/6. Every read of the Locked Echoes,
-- Slot actions and Status pages (twice, nothing advanced) reaches no lock,
-- unlock, request or other write entry of the adapter or the service and
-- changes no action, message, request, attempt or target state.
-- SETUP: real TOC boot per scenario and the real provider
-- Nexus.GetDiagnosticPageText (what /nexus log shows), with the AutoLock
-- fixture shape of batch_locked_units_autolock.lua. Synthetic records,
-- capacity and services only; no saved or private data. Spacing retry is not
-- exercised (it needs two Nexus writes within three seconds).
local B=dofile('tests/prototype/batch_repair_support.lua')
local C=B.Checker('triage_locked_diagnostics')
local printable=B.printable
local ROLLED={{spellId=200001,quality=1,stacks=1}}
local T=200050
local PAGES={'locked','autolock','state'}
-- The historical claim that Nexus has no lock/unlock write ("Nexus can only
-- read these, never lock/unlock them") and its variants. A page saying that
-- it writes nothing itself makes no such claim.
local IMPOSSIBLE={'can only read these','never lock/unlock them','never lock or unlock them','no server api to lock',
 'no lock/unlock api','nexus has no lock','only exposes the read-only','nexus cannot lock','nexus cannot unlock',
 "nexus can't lock","nexus can't unlock",'nexus can only read'}
local UNTRUSTED={'not trusted','untrusted','unavailable','unreadable','refused','not authoritative'}
local H,A

-- Native-shaped locked records (perks_service.lua 308-315) from spell 200060
-- on, one per occupied slot, holding the given copies.
local function Records(stacks)
 local t={}
 for i,s in ipairs(stacks) do
  local id=200059+i
  t[i]={spellId=id,stack=s,maxStack=5,quality=id%4}
 end
 return t
end
local function Singles(n) local s={};for i=1,n do s[i]=1 end;return Records(s) end
local function Capacity(n) ProjectEbonhold.PerkService.GetMaximumPermanentEchoes=function() return n end end

-- Header: a page's first line. Block: its lines before the first blank line
-- (on the Locked Echoes page, the header and the locked listing).
local function Header(text) return (text or ''):match('^([^\n]*)') end
local function Block(text) return ((text or '')..'\n\n'):match('^(.-)\n\n') end
local function LineWith(text,needle)
 for line in ((text or '')..'\n'):gmatch('([^\n]*)\n') do
  if line:find(needle,1,true) then return line end
 end
end
-- The first of `words` the text holds (case-insensitive), or nil.
local function Found(text,words)
 local lower=(text or ''):lower()
 for _,w in ipairs(words) do if lower:find(w,1,true) then return w end end
end
-- The ratio r/c of whole numbers.
local function Ratio(line,r,c) return (line or ''):find('%f[%d]'..r..'/'..c..'%f[%D]')~=nil end
-- Any n/6: a stated maximum of six.
local function OverSix(text) return (text or ''):find('%d/6%f[%D]')~=nil end
-- The whole number n in the line, not one side of a numeric ratio.
local function Token(line,n)
 line=line or ''
 local s=1
 while true do
  local a,b=line:find('%f[%d]'..n..'%f[%D]',s)
  if not a then return false end
  if not line:sub(b+1):match('^/%d') and not line:sub(1,a-1):match('%d/$') then return true end
  s=b+1
 end
end
-- A line of the block that states n held copies as copies.
local function CopiesStated(block,n)
 for line in ((block or '')..'\n'):gmatch('([^\n]*)\n') do
  if line:lower():find('cop',1,true) and Token(line,n) then return true end
 end
 return false
end
-- A locked state named not trusted, with no Wishlist comparison drawn from it.
local function Untrusted(page)
 return Found(Header(page),UNTRUSTED)~=nil and not (page or ''):lower():find('currently locked echo id',1,true)
end
-- The occupied records and capacity of the Slot actions trace's own line.
local function TraceRecords(text) return (text or ''):match('locked records: (%d+)/(%w+)') end

-- Real TOC boot: Automation ON, one owned copy of the target T, the plan's
-- locked-target bucket {T}, the given locked records and capacity, and the
-- autoLockEchoes option as given.
local function Boot(label,capacity,locked,autoLock)
 Nexus=nil;SlashCmdList=nil;NexusDB=nil;WishlistRealizerDB=nil
 H=dofile('tests/prototype/harness.lua');H.pendingRolls=40;H.playerLevel=30
 H.locked=locked
 H.Boot()
 A=Nexus.GameAdapter
 Capacity(capacity)
 C.setup(A.SetFirstLoadoutWishlistIdentity('Synthetic triage plan',ROLLED),label..': a Wishlist with no design of its own')
 local K=A.WishlistKey(ROLLED)
 Nexus.Store.Settings().autoLockEchoes=autoLock
 local granted=H.Clone(H.granted or {})
 granted['Echo 50']={{spellId=T,quality=(T-200000)%4}}
 H.granted=granted
 SlashCmdList.NEXUS('reroll off');SlashCmdList.NEXUS('freeze off');SlashCmdList.NEXUS('banish off')
 H.Notify();H.Advance(1)
 SlashCmdList.NEXUS('auto');H.Advance(2)
 C.setup(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(state)
  state.lockDesignTargetsBySlot=state.lockDesignTargetsBySlot or {}
  state.lockDesignTargetsBySlot[K]={[T]=true}
 end),label..': the locked-target bucket is written through the store owner')
 C.setup(type(A.LockPerk)=='function' and type(A.UnlockPerk)=='function',
  label..': GameAdapter.LockPerk and UnlockPerk are present')
end
local function Step(seconds) Nexus.RequestRecompute();H.Advance(seconds or 1.5) end

-- What a read must leave unchanged: the harness action, message and request
-- counts, the AutoLock evaluations and lifecycle counters, and the stored
-- attempt and target buckets.
local function Witness()
 local _,row=Nexus.MainInternals.StoreAuthorityOwner.ReadStateV1()
 row=type(row)=='table' and row or {}
 local stats=Nexus.RecomputeStats()
 return table.concat({#H.actions,#H.sent,H.grantedRequests or 0,H.slotRequests or 0,
  tostring(stats.autoLockEvaluations),B.Dump(stats.autoLockLifecycle),
  B.Dump(row.autoLockAttempts),B.Dump(row.lockDesignTargetsBySlot)},'|')
end
-- The three pages through the real provider, read twice with nothing
-- advanced, while every non-getter service entry and the adapter's lock and
-- request entries are counted (each still calls through). Returns the first
-- read, colour codes removed.
local function Passive(label)
 local svc,names,calls,restore=ProjectEbonhold.PerkService,{},{},{}
 for name,fn in pairs(svc) do
  if type(name)=='string' and type(fn)=='function' and not name:find('^Get') and not name:find('^Is')
   and not name:find('^Are') and not name:find('^Can') then names[#names+1]=name end
 end
 table.sort(names)
 local function Watch(owner,name,tag)
  local real=owner[name]
  if type(real)~='function' then return end
  owner[name]=function(...) calls[#calls+1]=tag..name;return real(...) end
  restore[#restore+1]=function() owner[name]=real end
 end
 local before=Witness()
 for _,name in ipairs(names) do Watch(svc,name,'service.') end
 for _,name in ipairs({'LockPerk','UnlockPerk','RequestGranted','RequestSlots'}) do Watch(A,name,'adapter.') end
 local first,second={},{}
 local ok,err=pcall(function()
  for _,key in ipairs(PAGES) do first[key]=Nexus.GetDiagnosticPageText(key) end
  for _,key in ipairs(PAGES) do second[key]=Nexus.GetDiagnosticPageText(key) end
 end)
 for i=#restore,1,-1 do restore[i]() end
 local after=Witness()
 local pages={}
 for _,key in ipairs(PAGES) do
  C.setup(ok and type(first[key])=='string',label..': the '..key..' page renders',err)
  pages[key]=B.Plain(type(first[key])=='string' and first[key] or '')
 end
 C.guard(#calls==0 and after==before,label..': reading the Locked Echoes, Slot actions and Status pages twice reaches'
  ..' no lock, unlock, request or other write entry and changes no action, message, request, attempt or target state',
  table.concat(calls,',')..(after==before and '' or ' | state changed'))
 C.guard(first.locked==second.locked and first.autolock==second.autolock,
  label..': a second read shows the same Locked Echoes and Slot actions text')
 local all=pages.locked..'\n'..pages.autolock..'\n'..pages.state
 C.guard(Found(all,IMPOSSIBLE)==nil,label..': no page claims Nexus cannot lock or unlock',Found(all,IMPOSSIBLE))
 print('OBSERVED',label,'header='..Header(pages.locked),'trace='..printable(LineWith(pages.autolock,'locked records:')),
  'target='..printable(LineWith(pages.autolock,'target '..T)),'step='..printable(LineWith(pages.autolock,'  -> ')),
  'history='..printable(LineWith(pages.autolock,' LOCK ')),'write/request calls='..#calls)
 return pages
end

C.scenario('A disabled, then enabled and awaiting: five records holding 1,1,1,3,1 at capacity 6',function()
 Boot('A',6,Records({1,1,1,3,1}),false)
 local l=A.LockedOwned()
 C.setup(l.synced==true and l.occupied==5 and A.MaxPermanentEchoes()==6,
  'A: five trusted records holding seven copies, live capacity 6',printable(l.occupied))
 Step()
 local p=Passive('A off')
 C.setup(p.autolock:find('AutoAllowed: true',1,true)~=nil,'A off: Automation is ON (the trace passed its first gate)')
 C.guard(p.autolock:find('autoLockEchoes setting: false',1,true)~=nil and p.state:find('autoLockEchoes=false',1,true)~=nil,
  'A off: the Slot actions trace and the Status page say locked-Echo slot automation is off')
 C.guard(p.autolock:find('no LockPerk/UnlockPerk attempts recorded',1,true)~=nil
  and B.Count(H,'lock')==0 and B.Count(H,'unlock')==0,'A off: the history shows no write attempt and none was made')
 local header=Header(p.locked)
 C.guard(Found(header,{'display only'})~=nil and Found(header,{'automation'})~=nil,
  'A off: the Locked Echoes header says display only and names the optional slot automation',header)
 C.expect(Ratio(header,5,6) and not p.locked:find('7/6',1,true),
  'A off (R1): the header states 5/6 occupied records, never the seven held copies over six',header)
 C.expect(CopiesStated(Block(p.locked),7),'A off (R1): the seven held copies are stated as copies, apart from the records',
  header)
 -- Enabled, every gate open: reading still writes nothing.
 Nexus.Store.Settings().autoLockEchoes=true
 Passive('A on, no step yet')
 C.guard(B.Count(H,'lock')==0,'A on: with a lock now permitted, reading the pages submits none',B.Count(H,'lock'))
 Step();Step()
 p=Passive('A awaiting')
 C.guard(p.autolock:find('autoLockEchoes setting: true',1,true)~=nil and p.state:find('autoLockEchoes=true',1,true)~=nil,
  'A awaiting: the trace and the Status page say the option is on')
 local last=H.actions[#H.actions] or {}
 C.guard(B.Count(H,'lock')==1 and last[1]=='lock' and last[2]==T and B.Count(H,'unlock')==0,
  'A awaiting: the automation step submitted one lock of the target and no unlock',B.Count(H,'lock'))
 local target=LineWith(p.autolock,'target '..T..' (Echo 50)') or ''
 C.guard(target:find('locked=false',1,true)~=nil and target:find('lifecycle=awaiting-confirmation',1,true)~=nil,
  'A awaiting: the trace holds the submitted lock as awaiting-confirmation, not locked',target)
 C.guard(p.autolock:find('LOCK Echo 50 (id='..T..') ok=true',1,true)~=nil,
  'A awaiting: the history records the submitted write attempt',LineWith(p.autolock,' LOCK '))
 C.guard(not Block(p.locked):find('id='..T,1,true) and not p.autolock:find('FULFILLED',1,true),
  'A awaiting: neither page shows the awaiting target as locked')
 local r,c=TraceRecords(p.autolock)
 C.setup(r=='5' and c=='6','A awaiting: the Slot actions trace reports 5/6 locked records',printable(r)..'/'..printable(c))
 C.expect(r~=nil and c~=nil and Ratio(Header(p.locked),r,c),
  'A awaiting (C1): the Locked Echoes header states the occupied records and capacity of the Slot actions trace',
  Header(p.locked))
end)

C.scenario('B full occupancy without a designed replacement, then a refused write',function()
 Boot('B',6,Singles(6),true)
 Step()
 local p=Passive('B full')
 C.guard(p.autolock:find('no explicit replacement pairing, so nothing destructive was attempted',1,true)~=nil,
  'B full: the trace says every slot is full and, with no designed replacement, nothing destructive was attempted',
  LineWith(p.autolock,'  -> '))
 C.guard(p.locked:find('This display changes nothing',1,true)~=nil,'B full: the Locked Echoes page says it changes nothing')
 C.guard(B.Count(H,'lock')==0 and B.Count(H,'unlock')==0,'B full: no lock and no unlock')
 local r,c=TraceRecords(p.autolock)
 C.guard(r=='6' and c=='6' and Ratio(Header(p.locked),r,c),
  'B full: with single-copy records the header agrees with the trace (6/6)',Header(p.locked))
 -- A slot frees; the service refuses the lock write it is sent.
 local refused,native=0,ProjectEbonhold.PerkService.LockPerk
 ProjectEbonhold.PerkService.LockPerk=function() refused=refused+1;return false end
 H.locked=Singles(5);H.Notify()
 Step();Step()
 p=Passive('B refused')
 ProjectEbonhold.PerkService.LockPerk=native
 C.guard(refused==1 and B.Count(H,'lock')==0 and B.Count(H,'unlock')==0,
  'B refused: one lock write reached the service, which refused it; it is not retried; no unlock',refused)
 C.guard(p.autolock:find('LOCK Echo 50 (id='..T..') ok=false err=refused',1,true)~=nil,
  'B refused: the history records the refused attempt and its error',LineWith(p.autolock,' LOCK '))
 local target=LineWith(p.autolock,'target '..T..' (Echo 50)') or ''
 C.guard(target:find('lifecycle=rejected',1,true)~=nil and p.autolock:find('rejected identity retained',1,true)~=nil,
  'B refused: the trace keeps the attempt rejected until an explicit retry or an authoritative change',target)
 C.guard(not Block(p.locked):find('id='..T,1,true),'B refused: the Locked Echoes page does not show the refused target as locked')
 r,c=TraceRecords(p.autolock)
 C.guard(r=='5' and c=='6' and Ratio(Header(p.locked),r,c),
  'B refused: with single-copy records the header agrees with the trace (5/6)',Header(p.locked))
end)

C.scenario('M occupied records, held copies and a known, unknown or untrusted capacity',function()
 Boot('M',6,{},false)
 local actions=#H.actions
 local p=Passive('M empty')
 C.guard(Ratio(Header(p.locked),0,6),'M empty: no records at capacity 6 read 0/6',Header(p.locked))
 Capacity(7);H.locked=Singles(7)
 C.setup(A.LockedOwned().synced==true,'M1: seven records at capacity 7 are trusted')
 p=Passive('M1 capacity 7')
 local h=Header(p.locked)
 C.expect(Ratio(h,7,7) and not OverSix(p.locked),'M1: seven occupied records at the live capacity 7 read 7/7, with no /6 maximum',h)
 Capacity(0);H.locked=Records({1,2,1})
 C.setup(A.MaxPermanentEchoes()==nil and A.LockedOwned().synced==true,
  'M2: the capacity getter answers 0 (unknown); three records holding four copies are trusted')
 p=Passive('M2 capacity unknown')
 h=Header(p.locked)
 C.expect(Found(h,{'unknown','unavailable'})~=nil and Token(h,3) and not OverSix(p.locked),
  'M2: the unknown capacity is named, the 3 occupied records are counted and no /6 maximum is stated',h)
 Capacity(6);H.locked=Singles(7)
 C.setup(A.LockedOwned().synced==false,'M3: seven records above capacity 6 are refused by the trust boundary')
 p=Passive('M3 refused read')
 C.expect(Untrusted(p.locked),'M3: the refused locked state is named not trusted, with no Wishlist comparison drawn from it',
  Header(p.locked))
 local getter=ProjectEbonhold.PerkService.GetLockedPerks
 ProjectEbonhold.PerkService.GetLockedPerks=function() error('synthetic unreadable locked state',0) end
 C.setup(A.LockedOwned().synced==false,'M4: an unreadable locked state is not trusted')
 p=Passive('M4 unreadable')
 ProjectEbonhold.PerkService.GetLockedPerks=getter
 C.expect(Untrusted(p.locked),'M4: the unreadable locked state is named unavailable, not zero locked, with no Wishlist comparison',
  Header(p.locked)..' | '..printable(LineWith(p.locked,'currently locked Echo ID')))
 C.guard(#H.actions==actions,'M: no game action',#H.actions-actions)
end)

C.finish('(the Locked Echoes page states trusted occupied records, held copies and a known or unknown capacity; reading the diagnostics never acts)')
