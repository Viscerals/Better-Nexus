-- Orb count refusal, part 1 of 2 (regression-first): a truthful refusal text.
-- When the current normal LockedOwned() read is refused only because it holds
-- more than six locked copies (its sample's rejection code is over_cap) while
-- rolled ownership and the assignment are ready, the Orb read refuses at its
-- trust gate. At b704660 it answers with the shared trust-gate text "Waiting
-- for current rolled and locked Echo data from the server." (core/OrbAdapter.lua,
-- O.Read). That reads as an unanswered server reply, although the data arrived
-- and Nexus refused its count.
-- Healthy behaviour (EXPECT, fails at b704660): that refusal says that Nexus
-- rejected the locked Echo data/count (orb_count_refusal_support R.Truthful:
-- names Nexus, says rejected or refused, names the locked data or its count,
-- one bounded line, no waiting wording), and the Orb window, its start reason,
-- Prepare and Acquire give that same text.
-- Unchanged (GUARD, holds at b704660): the refusal itself and stage
-- trust_locked; no progress and Start unavailable; the locked counts, their
-- sample and the projection counters; the readiness codes and the report block,
-- which carries no refusal text; Orb action ownership; every spend, choice and
-- lock gate, the ordinary-board gate and EchoWeaver's locked wait; the six-copy
-- cap itself (the same records holding six copies are trusted); the work of the
-- read (exactly the game getters and entries of the plain refusal of a malformed
-- table, and no request, send or save); and the diagnostic accessors, which read
-- no game state and send or save nothing. This is not a slots-versus-stacks
-- change: no cap, transfer or Wishlist limit, capacity getter or AutoLock rule
-- is changed; they are only guarded here.
-- Real TOC boot and modules, Orb adapter, runtime and window, support report;
-- the fake services of orbs_support.lua through locked_shape_support.lua:
-- artificial IDs and names; five native-shaped locked records (an array per
-- Echo name) holding 1, 1, 1, 3 and 1 copies. Pass-through call counters are
-- installed only around the work comparison and removed after it. No Orb run is
-- started; nothing is spent, selected or locked.
local H,T=dofile('tests/prototype/locked_shape_support.lua')
local R=dofile('tests/prototype/orb_count_refusal_support.lua')
local A,O,M=H.A,H.O,H.M
local printable=R.printable
local C=R.Checker('orb_count_refusal_truthful',T.realPcall)
local X=R.Fixture(H,T)
local WAIT_LOCKED='waiting for locked Echo state'

-- Whole seconds from here on.
H.now=math.floor(H.now)+100
local okPlan,whyPlan=X.Assign()
C.setup(okPlan and true or false,'fixture: slot 1 resolves its Wishlist through its association',whyPlan)
X.Trusted()
C.setup(A.AssignedWishlist().state=='ready','fixture: the assignment is ready',A.AssignedWishlist().state)

local function kinds(list)
 local n=0
 for _,k in ipairs(list) do n=n+H.Count(k) end
 return n
end
local ACTIONS={'orb-spend','take','banish','freeze','reroll','lock','unlock'}
local ACTIONS0=kinds(ACTIONS)

-- P1. The over-cap refusal: its text (EXPECT) and everything else (GUARD).
C.scenario('P1 the over-cap refusal',function()
 X.Trusted()
 local allowed0=T.serialize({A.OrdinaryBoardAllowed()})
 local charges0,actions0,sent0=O.charges,kinds(ACTIONS),#H.sent
 H.now=H.now+5
 local l,d,err=T.read(X.Over())
 C.setup(l~=nil and l.synced==false,'P1: fixture: the normal locked read of the five records is refused',err or (l and l.synced))
 l=l or {}
 C.guard(T.sig(l.bySpell)==T.sig(X.Want(X.OVER)),
  "P1: the read keeps each record's held copies ("..T.sig(X.Want(X.OVER))..')',T.sig(l.bySpell))
 C.guard(T.sum(l.byFamily)==7 and d.calls==1 and d.spells==5 and d.copies==7,
  'P1: seven copies of five Echoes, counted by one locked read',
  printable(T.sum(l.byFamily))..' '..d.calls..'/'..d.spells..'/'..d.copies)
 local t=T.trust() or {}
 C.guard(t.lockedSynced==false and t.lockedRejection=='over_cap' and t.lockedCopies==7 and t.lockedRawType=='table'
  and t.lockedSerial==d.serial,"P1: its ownership sample: over_cap, 7 copies, a table, that read's serial",
  printable(t.lockedRejection)..'/'..printable(t.lockedCopies)..'/'..printable(t.lockedSerial))
 C.setup(A.Owned().synced==true,'P1: fixture: rolled ownership is trusted')
 local db0=T.serialize(NexusDB)

 -- The real Orb read of that state.
 H.locked=X.Over()
 local ok,snap,why,stage=X.Read()
 print('OBSERVED','over-cap Orb read','stage='..printable(stage),'text='..printable(why))
 C.guard(ok and snap==nil,'P1: the Orb read still refuses',ok and printable(snap) or snap)
 C.guard(stage=='trust_locked','P1: at its trust gate: stage trust_locked',stage)
 local truthful,rule=R.Truthful(why)
 C.expect(truthful,'P1: the refusal says that Nexus rejected the locked Echo data or its count and does not read as an awaited server reply (unmet: '
  ..printable(rule)..')',why)

 -- The Orb window shows the same read.
 local s,shown=X.Window()
 C.setup(type(s)=='table','P1 window: fixture: the window read completes',shown and shown.error)
 s=s or {};shown=shown or {}
 C.guard(s.progress==nil and s.canStart==false and shown.start==false,'P1 window: no target progress, and Start is unavailable',
  printable(s.progress)..'/'..printable(s.canStart)..'/'..printable(shown.start))
 C.guard(type(s.assignment)=='table' and s.assignment.state=='ready','P1 window: the assignment is still ready')
 C.guard(type(shown.targets)=='string' and shown.targets:find('Target progress unavailable',1,true)==1,
  'P1 window: the targets line says that progress is unavailable',shown.targets)
 C.expect(s.error==why and R.Truthful(s.error)==true,'P1 window: the window refusal is that same truthful text',s.error)
 C.setup(type(s.persistence)=='table' and s.persistence.mode=='durable',
  'P1 window: fixture: local data is durable, so the start reason is the read refusal',type(s.persistence)=='table' and s.persistence.mode)
 C.expect(s.startReason==s.error and R.Truthful(s.startReason)==true,'P1 window: the start reason is that text',s.startReason)
 C.expect(type(shown.status)=='string' and R.Truthful(why)==true and shown.status:find(why,1,true)~=nil,
  'P1 window: and the status line shows it',shown.status)

 -- The readiness observation and the report keep their codes, not the text.
 local r=T.readiness() or {}
 local t2=T.trust() or {}
 C.guard(r.observed==true and r.stage=='trust_locked' and r.progress=='unavailable',
  'P1 readiness: the window read is recorded at stage trust_locked, progress unavailable',
  printable(r.stage)..'/'..printable(r.progress))
 C.guard(r.lockedSynced==false and r.lockedRejection=='over_cap' and r.lockedCopies==7,
  'P1 readiness: with the locked facts of that read: over_cap, 7 copies',
  printable(r.lockedRejection)..'/'..printable(r.lockedCopies))
 C.guard(T.int(r.lockedSerial) and r.lockedSerial==t2.lockedSerial,'P1 readiness: and the serial of that locked read',
  printable(r.lockedSerial)..' / '..printable(t2.lockedSerial))
 local lines=T.lines(T.prepared(),'Orb readiness')
 local tk=T.tokens(lines)
 C.guard(#lines>0 and tk.stage=='trust_locked' and tk['locked.rejection']=='over_cap' and tk['locked.copies']=='7'
  and tk.progress=='unavailable','P1 report: the Orb readiness block keeps its codes',
  printable(tk.stage)..'/'..printable(tk['locked.rejection'])..'/'..printable(tk['locked.copies'])..'/'..printable(tk.progress))
 local markers={R.FALLBACK}
 if type(why)=='string' and why~='' then markers[#markers+1]=why end
 local found=T.leaks(lines,markers)
 C.guard(#found==0,'P1 report: the block carries no refusal text, name or Echo ID',table.concat(found,','))

 -- Orb action ownership.
 C.guard(not A.Orbs.IsOwned(),'P1: no Orb action owner exists')
 local okA,token,aWhy=T.realPcall(A.Orbs.Acquire,{})
 C.guard(okA and token==nil and not A.Orbs.IsOwned(),'P1: Orb action ownership is still refused',okA and printable(token) or token)
 C.expect(aWhy==why and R.Truthful(aWhy)==true,'P1: Acquire refuses with the same truthful text',aWhy)
 -- Spending and choice: Prepare (both modes) refuses before any approval.
 for _,mode in ipairs({'assigned','single'}) do
  local okP,p,pWhy=T.realPcall(M.Prepare,mode)
  C.guard(okP and p==nil,'P1: Prepare('..mode..') is refused',okP and printable(p) or p)
  C.expect(pWhy==why and R.Truthful(pWhy)==true,'P1: Prepare('..mode..') refuses with the same truthful text',pWhy)
 end
 -- Gates and effects.
 C.guard(T.serialize({A.OrdinaryBoardAllowed()})==allowed0,'P1: the ordinary-board gate answers as before',allowed0)
 C.guard(O.charges==charges0,'P1: the Orb balance is unchanged',O.charges)
 C.guard(kinds(ACTIONS)==actions0,'P1: no spend, take, banish, freeze, reroll, lock or unlock was sent',kinds(ACTIONS)-actions0)
 C.guard(#H.sent==sent0,'P1: no message was sent',#H.sent-sent0)
 C.guard(T.serialize(NexusDB)==db0,'P1: saved data is unchanged')
 -- EchoWeaver keeps its locked wait for this view (as locked_shape_capture C4).
 H.playerLevel=80
 local owned=A.Owned()
 local cat=A.Catalog()
 local plan={requestedCounts={[410002]=1,[410007]=1,[200001]=1},lockedRequestedCounts={[410007]=1,[200001]=1},
  explicitRoles=true,wishedFamilies={},targets={}}
 local refused=T.read(X.Over())
 H.playerLevel=40
 local okD,decision=T.realPcall(Nexus.EchoWeaver.DecideNexus,{plan=plan,owned=owned,locked=refused,level=80,horizon=40,
  ordinaryBoardAllowed=true,board={cards={{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}}},
  charges={banish=5,reroll=5,freeze=5,trustworthy=true},catalog=cat})
 C.guard(okD and type(decision)=='table' and decision.type=='wait' and decision.reason==WAIT_LOCKED,
  'P1: EchoWeaver keeps its locked wait for this view',
  okD and type(decision)=='table' and (printable(decision.type)..'/'..printable(decision.reason)) or decision)
 X.Trusted()
end)

-- P2. The six-copy cap itself is unchanged: the same five records holding six
-- copies are trusted and the Orb read passes its trust gate.
C.scenario('P2 the six-copy cap is unchanged',function()
 X.Trusted()
 local l=T.read(X.AtCap())
 C.guard(l~=nil and l.synced==true and T.sig(l.bySpell)==T.sig(X.Want(X.AT_CAP)),
  'P2: the same five records holding six copies are trusted',l and T.sig(l.bySpell))
 local t=T.trust() or {}
 C.guard(t.lockedRejection=='none' and t.lockedCopies==6,'P2: their sample: no rejection, 6 copies',
  printable(t.lockedRejection)..'/'..printable(t.lockedCopies))
 H.locked=X.AtCap()
 local ok,snap,why,stage=X.Read()
 C.guard(ok and type(snap)=='table' and why==nil and stage==nil,'P2: the Orb read passes its trust gate',
  printable(stage)..' / '..printable(why))
 local s=X.Window()
 C.guard(type(s)=='table' and s.progress~=nil and s.error==nil,'P2: target progress is available',s and s.error)
 X.Trusted()
end)

-- P3. The work: the over-cap refusal reads exactly what the plain refusal of a
-- malformed table reads, no more; the diagnostic accessors read nothing.
C.scenario('P3 the work of the refusal and of the accessors',function()
 X.Trusted()
 local W=R.Spies(H,T)
 H.locked=X.Invalid()
 local plain=W.work(A.Orbs.Read)
 local plainSample=(T.trust() or {}).lockedRejection
 H.locked=X.Over()
 local over=W.work(A.Orbs.Read)
 local overSample=(T.trust() or {}).lockedRejection
 local c0=T.counters()
 local acc=W.work(function()
  A.OwnershipTrustView();A.LockedShapeView();M.ReadinessView();T.prepared()
 end)
 local c1=T.counters()
 W.restore()
 C.setup(plain.ok and plain.a==nil and plain.c=='trust_locked' and plain.b==R.FALLBACK and plainSample=='invalid_value',
  'P3: fixture: a malformed locked table within the cap is refused at trust_locked with the shared wait',
  printable(plain.c)..' / '..printable(plainSample)..' / '..printable(plain.b))
 C.setup(overSample=='over_cap','P3: fixture: the over-cap sample',overSample)
 C.guard(over.ok and over.a==nil and over.c=='trust_locked','P3: the over-cap read refuses at trust_locked',
  printable(over.c))
 C.guard(R.SameCalls(plain.calls,over.calls),
  'P3: the over-cap refusal calls exactly the game getters and entries of the plain refusal, no more',
  'over-cap {'..R.CallList(over.calls)..'} / plain {'..R.CallList(plain.calls)..'}')
 C.guard((over.calls['PerkService.GetLockedPerks'] or 0)==1 and (over.calls['GameAdapter.LockedOwned'] or 0)==1,
  'P3: one locked getter call, made by its one normal locked read',R.CallList(over.calls))
 C.guard(over.sent==0 and over.actions==0 and not over.saved,'P3: the read sends, acts on and saves nothing')
 C.guard(acc.ok and next(acc.calls)==nil,
  'P3: the diagnostic accessors and the report call no game getter, read, request, status, spend, choice, lock or write',
  R.CallList(acc.calls))
 C.guard(acc.sent==0 and acc.actions==0 and not acc.saved,'P3: they send, act on and save nothing')
 local moved=R.Moved(c0,c1)
 C.guard(#moved==0,'P3: no adapter counter or revision moved',table.concat(moved,', '))
 X.Trusted()
end)

C.guard(kinds(ACTIONS)==ACTIONS0,'no Orb was spent and nothing was taken, banished, frozen, rerolled, locked or unlocked',
 kinds(ACTIONS)-ACTIONS0)
C.guard(not A.Orbs.IsOwned(),'no Orb action owner was left')
C.finish('(the over-cap Orb refusal says that Nexus rejected the locked count; every gate and count is unchanged)')
