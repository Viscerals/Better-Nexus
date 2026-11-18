-- NX-02 semantic controls (stutter review, 2026-10-14). They pass on the
-- delivered build test.2026101502-3d52b0ed7044 and must keep passing after any
-- change that lets Orb display refreshes reuse an Echo reconciliation
-- (stutter_orb_display.lua). Every change below is made right after a display
-- refresh, so it falls inside any <=1 s display reuse window.
--
-- Required:
--  1. The next display refresh shows every change at once, notified or not:
--     in-place and replaced ownership, a malformed or unknown Echo, catalog
--     drift, loading, nil and unreadable data; ungrouped Echoes keep their own
--     group; display results are detached copies.
--  2. A pending Echo notification is reconciled by the next display refresh and
--     keeps its dirty marking.
--  3. An unnotified change reaches the Echo generations within 1.25 s of
--     display-only refreshes (reuse is bounded, never permanent).
--  4. A direct Orb read runs its own full reconciliation in each new frame
--     (orb_read_signature_cost), also right after a display refresh.
--  5. Start (Spend), Resume (recovery) and the pump (Select) read fresh: they
--     refuse an unnotified in-place change and run their own reconciliation.
-- Work unit as in stutter_orb_display.lua: PerkService.GetServerActiveSlot
-- reads outside a GameAdapter.Slots projection (one per full reconciliation).
local H=dofile('tests/prototype/orbs_support.lua')
local A,M,O=H.A,H.M,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

H.OrbPlan() -- the assigned plan: one copy of 410002 (quality 2)

-- Instruments: the foreign active-slot read and the public slot projection.
local S=H.service
local work={outside=0,inside=0,projections=0}
local depth=0
local rawActive=S.GetServerActiveSlot
local countingActive=function(...)
 if depth>0 then work.inside=work.inside+1 else work.outside=work.outside+1 end
 return rawActive(...)
end
S.GetServerActiveSlot=countingActive
local rawSlots=A.Slots
local function Leave(ok,...)
 depth=depth-1
 if not ok then error((...),0) end
 return ...
end
A.Slots=function(...)
 work.projections=work.projections+1;depth=depth+1
 return Leave(pcall(rawSlots,...))
end
local function Reset() for k in pairs(work) do work[k]=0 end end
local function Scans() return A.EchoReconcileStats().scans end
local function Later() H.now=H.now+.25 end
local function Show() Later();return M.Status(false) end -- one display refresh
local function Read() Later();return A.Orbs.Read() end   -- one direct (action-path) read
-- Raw Echo generations: the cached counters EchoReconcileStats().generations
-- (no reconciliation, no service read). Orb context.active carries the raw
-- activeSlot generation (OrbAdapter ctx: EchoActiveSlotGeneration); the active
-- value of PresentationRevisions also counts presentation-only knownness
-- changes, so it is not that measure. Index 2: activeSlot, 3: granted.
local function Generation(i)
 local field=assert(({[2]='activeSlot',[3]='granted'})[i],'Generation: no raw Echo field for '..tostring(i))
 return A.EchoReconcileStats().generations[field]
end
local ACTIVE,GRANTED=2,3
local function Text(r)
 return 'error='..tostring(r and r.error)..' reason='..tostring(r and r.startReason)
  ..' canStart='..tostring(r and r.canStart)..' missing='..tostring(r and r.progress and r.progress.rolledMissing)
end
local function Ready(label,r)
 check(type(r)=='table' and r.error==nil and type(r.progress)=='table' and r.progress.rolledMissing==1 and r.canStart==true,
  label..': the display shows one missing copy and Start available: '..Text(r))
end
local function Refused(label,r,text)
 check(type(r)=='table' and r.error==text and r.startReason==text and r.canStart==false and r.progress==nil,
  label..': the next display refresh shows "'..text..'": '..Text(r))
end
local function Complete(label,r)
 check(type(r)=='table' and r.error==nil and type(r.progress)=='table' and r.progress.rolledMissing==0 and r.canStart==false
  and r.startReason=='All rolled targets are already complete. No Orbs are needed.',
  label..': the next display refresh shows the owned target: '..Text(r))
end
local PREFIX='A missing target is currently unavailable: '
local DRIFT='The live Echo catalog entry is unavailable or changed. Wait for verified catalog data.'

-- SETUP: instrument calibration (literal).
Later();Reset();local s0=Scans()
A.EchoActiveSlotGeneration()
check(work.outside==1 and work.inside==0 and work.projections==0 and Scans()-s0==1,
 'SETUP: one reconciliation in a new frame reads the active slot once, outside any projection: outside='
 ..work.outside..' inside='..work.inside..' scans='..(Scans()-s0))
Reset();A.EchoActiveSlotGeneration()
check(work.outside==0,'SETUP: a second reconciliation in the same frame reuses the scan: outside='..work.outside)
Later();Reset();A.Slots()
check(work.outside==0 and work.inside==1 and work.projections==1,
 'SETUP: one slot projection reads the active slot once, inside the projection: outside='..work.outside..' inside='..work.inside)
Ready('SETUP baseline',Show())
Ready('SETUP baseline again',Show())

-- 1. Display freshness: the very next refresh shows each change.
-- 1a. Unnotified in-place ownership change: the target copy appears.
H.granted['Desired A']={{spellId=410002,quality=2}}
Complete('1a in-place granted change',Show())
H.granted['Desired A']=nil
Ready('1a restored',Show())

-- 1b. Reference replacement of the ownership mirror.
local original=H.granted
H.granted=H.Clone(original);H.granted['Desired A']={{spellId=410002,quality=2}}
Complete('1b replaced granted table',Show())
H.granted=original
Ready('1b restored',Show())

-- 1c. Unnotified in-place malformed copy count: the mirror is rejected.
local entry=H.granted['Disposable A'][1]
entry.stacks=0
Refused('1c in-place malformed copy count',Show(),'Echo ownership could not be verified.')
entry.stacks=nil
Ready('1c restored',Show())

-- 1d. Unnotified in-place Echo that is not in the catalog.
local list=H.granted['Disposable A']
list[2]={spellId=499999,quality=1}
Refused('1d in-place unknown Echo',Show(),'Echo ownership could not be verified.')
list[2]=nil
Ready('1d restored',Show())

-- 1e. Groups: a grouped Echo uses g:<groupId>; an ungrouped one keeps s:<spellId>.
local r=Show();Ready('1e',r)
local grouped,ungrouped=r.catalog[410002],r.catalog[200001]
check(type(grouped)=='table' and grouped.group=='g:4101' and grouped.available==true and grouped.sourceAvailable==true,
 '1e the grouped target row: group='..tostring(grouped and grouped.group)..' available='..tostring(grouped and grouped.available))
check(type(ungrouped)=='table' and ungrouped.group=='s:200001',
 '1e an Echo without a group keeps its own group: '..tostring(ungrouped and ungrouped.group))

-- 1f. Unnotified in-place catalog drift: the live entry no longer matches.
H.db[410002].groupId=4199
r=Show()
check(type(r)=='table' and r.error==nil and r.canStart==false and type(r.startReason)=='string'
 and r.startReason:sub(1,#PREFIX)==PREFIX and r.startReason:find(DRIFT,1,true)~=nil,
 '1f in-place catalog drift blocks Start at the next refresh: '..Text(r))
local drifted=r.catalog[410002]
check(type(drifted)=='table' and drifted.group=='g:4101' and drifted.available==false
 and drifted.sourceAvailable==false and drifted.availabilityReason==DRIFT,
 '1f the row keeps the published group and is not available: group='..tostring(drifted and drifted.group)
 ..' available='..tostring(drifted and drifted.available)..' reason='..tostring(drifted and drifted.availabilityReason))
H.db[410002].groupId=4101
Ready('1f restored',Show())

-- 1g. Loading: the game does not know the Orb state yet.
O.known=false
Refused('1g balance loading',Show(),"Waiting for the server's Orb balance. Use Recheck once it is available.")
O.known=true
Ready('1g restored',Show())

-- 1h. Nil data: the balance read returns nothing.
local charges=O.charges
O.charges=nil
Refused('1h nil balance',Show(),"The server's Orb balance is invalid.")
O.charges=charges
Ready('1h restored',Show())

-- 1i. Unreadable data: the offer read raises.
local rawChoice=S.GetCurrentChoice
S.GetCurrentChoice=function() error('synthetic unreadable choice') end
Refused('1i unreadable offer',Show(),'The current Echo choices are unavailable.')
S.GetCurrentChoice=rawChoice
Ready('1i restored',Show())

-- 1j. Detached display state: caller edits do not reach the next result.
local r1=Show();Ready('1j',r1)
r1.progress.rolledMissing=99;r1.config.name='Edited by caller'
local copyRow=r1.catalog[410002];copyRow.available=false;copyRow.group='edited'
check(r1.catalog[410002].available==true and r1.catalog[410002].group=='g:4101',
 '1j each catalog access returns a fresh copy')
local r2=Show();Ready('1j next refresh',r2)
check(r2~=r1 and r2.progress~=r1.progress and r2.config.name~='Edited by caller'
 and r2.catalog[410002].available==true and r2.catalog[410002].group=='g:4101',
 '1j caller edits to one display result never reach the next')

-- 2. A pending Echo notification is reconciled by the next display refresh.
Ready('2 SETUP',Show())
A.ConsumeDirty()
local g=Generation(GRANTED)
H.granted['Excess high']={{spellId=410006,quality=3}}
H.Notify()
Reset();r=Show()
check(work.outside==1,'2 a display refresh with a pending Echo notification runs one full reconciliation: '..work.outside)
check(Generation(GRANTED)==g+1,'2 the notified change moves the granted generation once: '..Generation(GRANTED)..' after '..g)
local _,_,data=A.ConsumeDirty()
check(data==true,'2 the notified change keeps its dirty marking: '..tostring(data))
check(type(r)=='table' and r.error==nil and type(r.progress)=='table' and r.progress.rolledMissing==1,
 '2 the display still shows the plan: '..Text(r))
H.granted['Excess high']=nil;H.Notify()
Ready('2 restored',Show());A.ConsumeDirty()

-- 3. Bounded display latency for an unnotified in-place change.
check(Read(),'3 SETUP: anchor direct read')
g=Generation(GRANTED)
H.granted['Desired A']={{spellId=410002,quality=2}}
Complete('3 first refresh after the unnotified change',Show())
for _=2,5 do Show() end
check(Generation(GRANTED)==g+1,
 '3 display-only refreshes reconcile an unnotified change within 1.25 s: granted generation '..Generation(GRANTED)..' after '..g)
H.granted['Desired A']=nil
check(Read() and Generation(GRANTED)==g+2,'3 restored: the next direct read reconciles the change back: '..Generation(GRANTED))
Ready('3 restored',Show())

-- 4. A direct read right after a display refresh runs its own reconciliation.
local before=Generation(ACTIVE)
local slot=H.perks.serverActiveSlot
H.perks.serverActiveSlot=slot+1
Reset();local s=Read()
check(type(s)=='table' and work.outside==1,
 '4 a direct Orb read 0.25 s after a display refresh runs one full reconciliation: '..work.outside)
check(Generation(ACTIVE)==before+1 and s.context.active==before+1,
 '4 it sees the unnotified in-place active-slot change: generation '..Generation(ACTIVE)..' context '..tostring(s.context.active)..' after '..before)
H.perks.serverActiveSlot=slot
check(Read() and Generation(ACTIVE)==before+2,'4 the change back is seen by the next direct read: '..Generation(ACTIVE))
Ready('4 SETUP',Show())
S.GetServerActiveSlot=function() error('synthetic slot read failure') end
s=Read()
check(type(s)=='table' and s.context.active==nil,'4 a failed reconciliation carries no generation: '..tostring(s and s.context.active))
S.GetServerActiveSlot=countingActive
s=Read()
check(type(s)=='table' and type(s.context.active)=='number','4 restored: the next direct read carries a generation')

-- 5. Actions read fresh after a display refresh that offered Start.
check(M.SetLimit(3),'5 SETUP: limit 3')
-- 5a. Spend precondition: the balance drops to 0 in place, unnotified.
Ready('5a SETUP',Show())
O.charges=0
Later();Reset()
local ok,err=M.Start()
check(ok==nil and err=='No confirmed Orbs are available.' and H.Count('orb-spend')==0,
 '5a Start refuses the unnotified empty balance: '..tostring(ok)..' '..tostring(err)..' spends '..H.Count('orb-spend'))
check(work.outside>=1,'5a the Start path runs its own reconciliation: '..work.outside)
O.charges=charges

-- 5b. Spend precondition: unnotified in-place catalog drift of the target.
Ready('5b SETUP',Show())
H.db[410002].groupId=4199
Later();ok,err=M.Start()
check(ok==nil and type(err)=='string' and err:sub(1,#PREFIX)==PREFIX and err:find(DRIFT,1,true)~=nil
 and H.Count('orb-spend')==0,'5b Start refuses the drifted target: '..tostring(err)..' spends '..H.Count('orb-spend'))
H.db[410002].groupId=4101

-- 5c. Spend: Start submits exactly one Orb after its own fresh read.
Ready('5c SETUP',Show())
Later();Reset()
ok,err=M.Start()
check(ok==true and H.Count('orb-spend')==1,'5c Start submits one Orb spend: '..tostring(err)..' spends '..H.Count('orb-spend'))
check(work.outside>=1,'5c the Start and Spend path runs its own reconciliation: '..work.outside)

-- 5d. Recovery: Pause, then Resume reads fresh and repeats nothing.
check(M.Pause()==true,'5d SETUP: pause with the spend pending')
Show()
Later();Reset()
ok,err=M.Resume()
check(ok==true,'5d Resume continues the paused run: '..tostring(err))
check(work.outside>=1,'5d the Resume path runs its own reconciliation: '..work.outside)
check(H.Count('orb-spend')==1,'5d Resume repeats no spend: '..H.Count('orb-spend'))

-- 5e. Select: the offer appears, but the game holds another action (an
-- unnotified in-place host latch). The pump selects nothing; once the latch
-- clears, the next pump selects the target after its own fresh read.
O.charges=O.charges-1;O.offer=true
H.Board({{spellId=410002,quality=2},{spellId=410003,quality=0},{spellId=410004,quality=3}})
H.perks.pendingFreezeIndex=0
Later();M.Pump()
check(H.Count('take')==0,'5e no selection while the game holds another pending action: '..H.Count('take'))
H.perks.pendingFreezeIndex=nil
Later();Reset();M.Pump()
local last=H.actions[#H.actions]
check(H.Count('take')==1 and last and last[1]=='take' and last[2]==410002,
 '5e the next pump selects the offered target once: takes '..H.Count('take'))
check(work.outside>=1,'5e the Select path runs its own reconciliation: '..work.outside)
check(H.Count('orb-spend')==1,'5e no extra spend: '..H.Count('orb-spend'))

-- 6. Extra display-mode guards (phase 04-nx02-extra-guards). The accepted
-- future display read is A.Orbs.Read('display'); the baseline ignores the
-- argument and reads fully, so every guard passes now. After the NX-02 fix a
-- display read may reuse the last reconciliation for at most 1 s, but never
-- across a PerkService or character change, after a rejected or unavailable
-- snapshot, with a notification pending, or for a caller-supplied window.
-- Every shown field stays current on its own.
local function Display() Later();return A.Orbs.Read('display') end
local function C(x,k) if type(x)=='table' and type(x.context)=='table' then return x.context[k] end end
local function Rejected(field) return A.EchoReconcileStats().rejected[field] end
local live,liveSlot=ProjectEbonhold.PerkService,H.perks.serverActiveSlot
local d=Display()
check(live==S and type(C(d,'active'))=='number',
 '6 SETUP: a display read returns a state with an Echo generation: '..tostring(C(d,'active')))

-- 6a. PerkService reference swap right after a display read: the new service
-- reports another active slot.
local other={};for k,v in pairs(live) do other[k]=v end
other.GetServerActiveSlot=function(...) return countingActive(...)+1 end
local a0=Generation(ACTIVE)
ProjectEbonhold.PerkService=other
local sc=Scans();Reset();d=Display()
check(C(d,'svc')==other and Scans()-sc==1 and work.outside==1,
 '6a a display read after a PerkService swap reconciles with the new service: scans '..(Scans()-sc)..' reads '..work.outside)
check(Generation(ACTIVE)==a0+1 and C(d,'active')==a0+1,
 '6a it carries the new service\'s slot generation, not the old snapshot\'s: '..Generation(ACTIVE)
 ..' context '..tostring(C(d,'active'))..' after '..a0)
ProjectEbonhold.PerkService=live
sc=Scans();d=Display()
check(C(d,'svc')==live and Scans()-sc==1 and Generation(ACTIVE)==a0+2 and C(d,'active')==a0+2,
 '6a the restored service is reconciled by the next display read: scans '..(Scans()-sc)..' generation '..Generation(ACTIVE))

-- 6b. Character GUID change right after a display read.
local rawGUID=UnitGUID
UnitGUID=function() return '0x0000000000000002' end
sc=Scans();d=Display()
check(C(d,'guid')=='0x0000000000000002' and Scans()-sc==1,
 '6b a display read after a character change reconciles for that character: guid '..tostring(C(d,'guid'))..' scans '..(Scans()-sc))
UnitGUID=rawGUID
sc=Scans();d=Display()
check(C(d,'guid')=='0x0000000000000001' and Scans()-sc==1,
 '6b the restored character is reconciled by the next display read: guid '..tostring(C(d,'guid'))..' scans '..(Scans()-sc))

-- 6c. A failed active-slot read, recorded by a default reader, is retried by
-- the very next display read.
S.GetServerActiveSlot=function() error('synthetic slot read failure') end
Later();local failed=A.EchoActiveSlotGeneration()
check(failed==nil and Rejected('activeSlot')=='GetServerActiveSlot:error',
 '6c a failed slot read carries no generation: '..tostring(failed)..' '..tostring(Rejected('activeSlot')))
S.GetServerActiveSlot=countingActive
sc=Scans();Reset();d=Display()
check(Scans()-sc==1 and work.outside==1 and type(C(d,'active'))=='number' and Rejected('activeSlot')==nil,
 '6c the next display read retries at once: scans '..(Scans()-sc)..' context '..tostring(C(d,'active')))

-- 6d. An invalid active slot, recorded by a default reader, is retried by the
-- very next display read.
S.GetServerActiveSlot=function(...) countingActive(...);return -1 end
Later();failed=A.EchoActiveSlotGeneration()
check(failed==nil and Rejected('activeSlot')=='echo:scalar',
 '6d an invalid slot carries no generation: '..tostring(failed)..' '..tostring(Rejected('activeSlot')))
S.GetServerActiveSlot=countingActive
sc=Scans();d=Display()
check(Scans()-sc==1 and type(C(d,'active'))=='number' and Rejected('activeSlot')==nil,
 '6d the next display read retries at once: scans '..(Scans()-sc)..' context '..tostring(C(d,'active')))

-- 6e. PerkService missing: the display refuses, another reader records the
-- unavailable snapshot, and the next display read reconciles the restored one.
local g0=Generation(GRANTED)
ProjectEbonhold.PerkService=nil
Later();local u,why=A.Orbs.Read('display')
check(u==nil and why=='Orb mode is unavailable: the client does not expose PerkService.GetGrantedPerks.',
 '6e the display refuses a missing PerkService: '..tostring(why))
A.EchoActiveSlotGeneration()
check(Generation(GRANTED)==g0+1,'6e another reader records the unavailable snapshot: '..Generation(GRANTED)..' after '..g0)
ProjectEbonhold.PerkService=live
sc=Scans();Reset();d=Display()
check(type(C(d,'active'))=='number' and Scans()-sc==1 and work.outside==1 and Generation(GRANTED)==g0+2,
 '6e the restored service is reconciled by the next display read: scans '..(Scans()-sc)..' granted generation '..Generation(GRANTED))

-- 6f. Unreadable ownership mirror: the display refuses, another reader records
-- the rejected field, and the next display read reconciles the restored one.
local rawGranted=S.GetGrantedPerks
g0=Generation(GRANTED)
S.GetGrantedPerks=function() error('synthetic ownership read failure') end
Later();u,why=A.Orbs.Read('display')
check(u==nil and why=='Echo ownership could not be read.','6f the display refuses an unreadable mirror: '..tostring(why))
A.EchoActiveSlotGeneration()
check(Generation(GRANTED)==g0+1 and Rejected('granted')=='GetGrantedPerks:error',
 '6f another reader records the rejected mirror: '..Generation(GRANTED)..' after '..g0..' '..tostring(Rejected('granted')))
S.GetGrantedPerks=rawGranted
sc=Scans();d=Display()
check(type(C(d,'active'))=='number' and Scans()-sc==1 and Generation(GRANTED)==g0+2 and Rejected('granted')==nil,
 '6f the restored mirror is reconciled by the next display read: scans '..(Scans()-sc)..' granted generation '..Generation(GRANTED))

-- 6g. A pending notification is reconciled by the next display read.
Display();A.ConsumeDirty()
local g1=Generation(GRANTED)
H.granted['Excess high']={{spellId=410006,quality=3}}
H.Notify()
sc=Scans();d=Display()
check(type(d)=='table' and Scans()-sc==1 and Generation(GRANTED)==g1+1,
 '6g a display read with a pending notification reconciles it: scans '..(Scans()-sc)..' granted generation '..Generation(GRANTED)..' after '..g1)
local _,_,dirty=A.ConsumeDirty()
check(dirty==true,'6g the notified change keeps its dirty marking: '..tostring(dirty))
H.granted['Excess high']=nil;H.Notify();Display();A.ConsumeDirty()

-- 6h. Shown context fields are read at each display read, whatever is reused.
H.perks.serverActiveSlot=liveSlot+1
d=Display()
check(C(d,'slot')==liveSlot+1,'6h the next display read shows the in-place slot: '..tostring(C(d,'slot')))
H.perks.serverActiveSlot=liveSlot
local buildSlots=H.perks.serverBuildSlots
H.perks.serverBuildSlots=nil
d=Display()
check(C(d,'slotKnown')==false and C(d,'slot')==liveSlot,
 '6h build-slot data not loaded: slotKnown '..tostring(C(d,'slotKnown'))..' slot '..tostring(C(d,'slot')))
H.perks.serverBuildSlots=buildSlots
d=Display()
check(C(d,'slotKnown')==true,'6h build-slot data back: slotKnown '..tostring(C(d,'slotKnown')))

-- 6i. Unreadable Orb state (not a boolean) is shown by the next display read.
O.known=nil
Later();u,why=A.Orbs.Read('display')
check(u==nil and why=="The game's Orb state could not be read. No Orb will be spent.",
 '6i the display refuses an unreadable Orb state: '..tostring(why))
O.known=true
check(type(C(Display(),'active'))=='number','6i restored: the next display read succeeds')

-- 6j. No caller value opens a reuse window over 1 s: 1.25 s after a fresh
-- reconciliation, each call sees an unnotified in-place slot change.
local windows={
 {'A.Orbs.Read("display")',function() return C(A.Orbs.Read('display'),'active') end},
 {'A.Orbs.Read(3600)',function() return C(A.Orbs.Read(3600),'active') end},
 {'A.EchoActiveSlotGeneration(3600)',function() return A.EchoActiveSlotGeneration(3600) end},
 {'A.EchoActiveSlotGeneration(math.huge)',function() return A.EchoActiveSlotGeneration(math.huge) end},
 {'A.EchoActiveSlotGeneration(-1)',function() return A.EchoActiveSlotGeneration(-1) end},
 {'A.EchoActiveSlotGeneration(0/0)',function() return A.EchoActiveSlotGeneration(0/0) end},
 {'A.EchoActiveSlotGeneration("display")',function() return A.EchoActiveSlotGeneration('display') end},
 {'A.EchoActiveSlotGeneration(true)',function() return A.EchoActiveSlotGeneration(true) end},
}
local slotNow=liveSlot
for _,w in ipairs(windows) do
 Later();local anchor=A.EchoActiveSlotGeneration()
 slotNow=slotNow==liveSlot and liveSlot+1 or liveSlot
 H.perks.serverActiveSlot=slotNow
 H.now=H.now+1.25
 local okCall,gen=pcall(w[2])
 check(okCall and type(anchor)=='number' and gen==anchor+1,
  '6j '..w[1]..' 1.25 s after a reconciliation sees the in-place slot change: '..tostring(gen)..' after '..tostring(anchor))
end

S.GetServerActiveSlot,A.Slots=rawActive,rawSlots
print('PASS Orb display freshness, notification, bounded latency, direct read and fresh Start/Resume/Select controls; '..checks..' checks')
