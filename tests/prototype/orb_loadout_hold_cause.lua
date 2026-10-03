-- Diagnostics for the Orb loadout hold (see orb_loadout_hold_repro). The accepted
-- code held an unresolved Orb action with one flag, `loadoutChanged`, that eight
-- different scenarios set alike (four recorded cause names), and its report named neither the original slot nor
-- the cause. This test pins the read-only visibility added for support, and the
-- rules that keep it honest:
--  1. The owner's view and the support report name the original slot, the slot
--     read now, the loadout check, the cause the hold was first set for, whether
--     an offer is recorded, and the requirements the record itself shows unmet.
--  2. The cause is recorded ONCE, at the moment the hold is first set, from that
--     observation. A later observation never rewrites it.
--  3. A hold that was set without a cause (an earlier build) stays "not recorded".
--     It is never filled in from what is seen later, and a missing original slot
--     is never inferred.
--  4. The new persisted fields are a short name and two small whole numbers (the slot seen
--     then, and the clock time the hold was first set) and are validated on read: a
--     hostile saved value is never shown and never raises.
--  5. Nothing changes what the code does: no rule, refusal, spend or choice.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local S=dofile('tests/prototype/orb_loadout_hold_support.lua')

local function Line3()
 local lines=Nexus.SupportReport.OrbLines()
 return lines[3],lines
end
local function Has(text,part,m)check(text and text:find(part,1,true)~=nil,m..' ['..tostring(part)..'] in: '..tostring(text))end
local function Same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not Same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local function ListText(list)return table.concat(list or {},',')end

-- 1 and 2. Each cause records its cause once and shows it.
local CAUSE_TEXT={
 NO_ORIGINAL_SLOT='no original slot in the record',
 SLOT_DIFFERS='slot differed (slot data received)',
 SLOT_PUSHED='slot pushed before the slot data',
 SLOT_DIFFERS_UNVERIFIED='slot differed (client reports no slot data)',
}
for _,cause in ipairs(S.CAUSES)do
 local H,M,A,O,src,slots=S.Build(cause)
 local name=cause.name;local e=cause.expect
 local view=Nexus.OrbRuntime.RecoveryView()
 check(view.loadoutCause==e.cause,name..': the cause recorded when the hold was first set: '..tostring(view.loadoutCause))
 check(view.loadoutSeenSlot==e.seen,name..': the slot seen then: '..tostring(view.loadoutSeenSlot))
 check(type(view.loadoutSeenAt)=='number' and view.loadoutSeenAt>=1700000000 and view.loadoutSeenAt<=time(),name..': the clock time the hold was first set: '..tostring(view.loadoutSeenAt))
 check(view.originalSlot==e.original and view.originalSlotState==(e.original==nil and 'absent' or 'recorded'),
  name..': the original slot: '..tostring(view.originalSlot)..'/'..tostring(view.originalSlotState))
 check(view.slotRead==true and view.slotNow==e.now and view.slotNowKnown==e.nowKnown,
  name..': the slot read now: '..tostring(view.slotNow)..'/'..tostring(view.slotNowKnown))
 check(view.loadoutCheck=='CHANGED' and view.loadoutChanged==true,name..': the check and the latch')
 check(view.offerRecorded==true and ListText(view.unmet)=='loadout,choice',name..': the record shows two unmet requirements: '..ListText(view.unmet))
 local receipt=S.Receipt()
 check(receipt.loadoutCause==e.cause and receipt.loadoutObservedSlot==e.seen and receipt.loadoutObservedAt==view.loadoutSeenAt,name..': the cause is persisted with the receipt')
 local line3,lines=Line3()
 check(#lines==3 and lines[1]:find('waiting for=loadout',1,true),name..': a third support line follows the two existing ones')
 Has(line3,'original slot='..(e.original==nil and 'not recorded' or tostring(e.original)),name)
 Has(line3,'slot now='..(e.now==nil and 'not reported' or tostring(e.now))..' ('..(e.nowKnown==true and 'data received' or e.nowKnown==false and 'data not yet received' or 'client reports no slot data')..')',name)
 Has(line3,'check=changed',name);Has(line3,'hold cause='..CAUSE_TEXT[e.cause],name)
 if e.seen~=nil then Has(line3,'saw slot '..tostring(e.seen),name)end
 Has(line3,', set at '..date('%Y-%m-%d %H:%M:%S',view.loadoutSeenAt)..';',name)
 Has(line3,'offer recorded=yes',name);Has(line3,'unmet in record=loadout,choice',name)
 check(#line3<400 and not line3:find('[%z\1-\31]'),name..': the line is bounded')
 -- Idempotent: more passes, more rechecks, a return to the original slot and a
 -- second reload change nothing in the receipt.
 local snapshot=H.Clone(S.Receipt())
 S.Rechecks(H,M,3)
 H.perks.serverActiveSlot=e.original or 1;H.perks.serverBuildSlots=slots;S.Pass(H,M,A);S.Rechecks(H,M,2)
 M=S.Reload(H);H.perks.serverActiveSlot=e.original or 1;H.perks.serverBuildSlots=slots;S.Pass(H,M,A);S.Rechecks(H,M,2)
 check(Same(S.Receipt(),snapshot),name..': passes, a return to the original slot and a reload do not change the receipt')
 check(Nexus.OrbRuntime.RecoveryView().loadoutCause==e.cause,name..': the cause survives the reload')
end

-- 2. The cause is the first observation. A later, different slot does not rewrite it.
do
 local H,M,A,O,src,slots=S.Build(S.CAUSES[1])
 check(S.Receipt().loadoutCause=='SLOT_DIFFERS' and S.Receipt().loadoutObservedSlot==2,'first observation: slot 2')
 local firstAt=S.Receipt().loadoutObservedAt
 check(type(firstAt)=='number','first observation: a clock time')
 H.advanceClock=true;H.Advance(120)
 H.perks.serverActiveSlot=3;S.Pass(H,M,A);S.Rechecks(H,M,3)
 check(S.Receipt().loadoutObservedAt==firstAt and time()>firstAt+60,'a later pass, 2 minutes on, does not rewrite the clock time')
 local view=Nexus.OrbRuntime.RecoveryView()
 check(S.Receipt().loadoutCause=='SLOT_DIFFERS' and S.Receipt().loadoutObservedSlot==2,'a later slot 3 does not rewrite the recorded cause or the slot seen then')
 check(view.slotNow==3 and view.loadoutSeenSlot==2,'the live slot is 3; the recorded one is 2')
 Has(select(1,Line3()),'slot now=3','the live slot is shown');Has(select(1,Line3()),'saw slot 2','the recorded slot is shown')
end

-- 2b. A reload that has no slot data yet: the live slot facts say so, and the recorded cause is untouched.
do
 local H,M,A,O,src,slots=S.Build(S.CAUSES[1])
 M=S.Reload(H);H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=nil;S.Pass(H,M,A)
 local v=Nexus.OrbRuntime.RecoveryView()
 check(v.slotRead==true and v.slotNow==0 and v.slotNowKnown==false and v.loadoutCheck=='CHANGED','2b: slot 0, data not yet received, the latch reads changed')
 check(v.loadoutCause=='SLOT_DIFFERS' and v.loadoutSeenSlot==2,'2b: the recorded cause is the first observation, not this read')
 Has(select(1,Line3()),'slot now=0 (data not yet received)','2b')
end

-- 3. A hold set without a cause stays "not recorded" (an earlier build).
for _,variant in ipairs({
 {name='old hold, slot data known and different',edit=function(row,state)row.loadoutCause=nil;row.loadoutObservedSlot=nil;row.loadoutObservedAt=nil;state.loadoutCause=nil;state.loadoutObservedSlot=nil;state.loadoutObservedAt=nil end},
 {name='old hold, original slot missing',edit=function(row,state)
   row.loadoutCause=nil;row.loadoutObservedSlot=nil;row.loadoutObservedAt=nil;state.loadoutCause=nil;state.loadoutObservedSlot=nil;state.loadoutObservedAt=nil
   row.originalSlot=nil;state.originalSlot=nil end,absent=true},
})do
 local H,M,A,O,src,slots=S.Build(S.CAUSES[1])
 M=S.Reload(H,variant.edit)
 for _,slot in ipairs({0,2,3,1})do
  H.perks.serverActiveSlot=slot
  if slot==0 then H.perks.serverBuildSlots=nil else H.perks.serverBuildSlots=slots end
  S.Pass(H,M,A);S.Rechecks(H,M,2)
  check(Nexus.OrbRuntime.RecoveryView().slotNowKnown==(slot~=0),variant.name..': slot '..slot..': the slot-data state is as set')
 end
 local view=Nexus.OrbRuntime.RecoveryView()
 check(view.loadoutChanged==true and view.loadoutCause==nil and view.loadoutSeenSlot==nil,variant.name..': the cause stays not recorded')
 check(S.Receipt().loadoutCause==nil and S.Receipt().loadoutObservedSlot==nil and S.Receipt().loadoutObservedAt==nil,variant.name..': nothing was written into the receipt after the fact')
 local wantOriginal=1;if variant.absent then wantOriginal=nil end
 check(S.Receipt().originalSlot==wantOriginal,variant.name..': the original slot is not inferred or filled in')
 check(view.originalSlotState==(variant.absent and 'absent' or 'recorded'),variant.name..': the original slot state is the receipt\'s own')
 local line3=Line3()
 Has(line3,'hold cause=not recorded',variant.name)
 check(not line3:find('saw slot',1,true) and not line3:find('set at',1,true),variant.name..': no slot or time is claimed for a cause that was not recorded')
 -- The current facts are still shown, as current facts.
 check(view.slotNow==1 and view.slotNowKnown==true and view.loadoutCheck=='CHANGED',variant.name..': the live slot and the latch are shown as such')
end

-- 3b. A receipt without a hold shows no cause, and its requirement list differs by what is missing.
do
 local H,M,A,O=S.Fresh()
 local src,slots=S.SpendOfferNoChoice(H,M,A,O)
 H.perks.pendingSelectSpellId=nil
 M=S.Reload(H);S.Pass(H,M,A);S.Rechecks(H,M,2)
 local view=Nexus.OrbRuntime.RecoveryView()
 check(view.loadoutChanged==false and view.loadoutCause==nil and view.loadoutCheck=='SAME' and view.recovery=='OFFER_OPEN','no hold: the offer is open and the loadout is the same')
 check(ListText(view.unmet)=='choice' and view.offerRecorded==true,'no hold: only the choice is unmet')
 local line3=Line3()
 Has(line3,'check=same','no hold');Has(line3,'hold cause=none recorded','no hold');Has(line3,'unmet in record=choice','no hold')
end
-- 3c. A held receipt that has a recorded choice lists only the loadout.
do
 local H,M,A,O=S.Fresh()
 S.Loadouts(H,A)
 assert(M.Start(3));H.Offer()
 check(H.Count('take')==1 and S.Receipt().selectedKey~=nil,'setup: one automatic choice recorded')
 H.perks.serverActiveSlot=2;S.Pass(H,M,A)
 local view=Nexus.OrbRuntime.RecoveryView()
 check(view.loadoutCause=='SLOT_DIFFERS' and view.loadoutSeenSlot==2 and view.choiceSent==true,'live change after a recorded choice: cause recorded')
 check(ListText(view.unmet)=='loadout','a recorded choice leaves only the loadout unmet: '..ListText(view.unmet))
 Has(select(1,Line3()),'unmet in record=loadout','recorded choice')
end

-- 4. Hostile saved values are never shown and never raise; the persisted fields are bounded.
do
 local HUGE=string.rep('X',500)
 local CASES={
  {name='long cause string',edit=function(p)p.loadoutCause=HUGE end,cause=false},
  {name='cause table',edit=function(p)p.loadoutCause={'SLOT_DIFFERS'} end,cause=false},
  {name='unknown cause name',edit=function(p)p.loadoutCause='MADE_UP' end,cause=false},
  {name='cause with control bytes',edit=function(p)p.loadoutCause='SLOT_DIFFERS'..string.char(1,10,7) end,cause=false},
  {name='negative seen slot',edit=function(p)p.loadoutObservedSlot=-1 end,cause=true},
  {name='fractional seen slot',edit=function(p)p.loadoutObservedSlot=1.5 end,cause=true},
  {name='huge seen slot',edit=function(p)p.loadoutObservedSlot=1e12 end,cause=true},
  {name='string seen slot',edit=function(p)p.loadoutObservedSlot='2' end,cause=true},
  {name='table seen slot',edit=function(p)p.loadoutObservedSlot={2} end,cause=true},
  {name='nan seen slot',edit=function(p)p.loadoutObservedSlot=0/0 end,cause=true},
  {name='negative clock time',edit=function(p)p.loadoutObservedAt=-1 end,cause=true,seen=2,at=false},
  {name='clock time before 2000',edit=function(p)p.loadoutObservedAt=5 end,cause=true,seen=2,at=false},
  {name='clock time after 2100',edit=function(p)p.loadoutObservedAt=1e12 end,cause=true,seen=2,at=false},
  {name='fractional clock time',edit=function(p)p.loadoutObservedAt=1700000000.5 end,cause=true,seen=2,at=false},
  {name='string clock time',edit=function(p)p.loadoutObservedAt='1700000000' end,cause=true,seen=2,at=false},
  {name='table clock time',edit=function(p)p.loadoutObservedAt={1700000000} end,cause=true,seen=2,at=false},
  {name='nan clock time',edit=function(p)p.loadoutObservedAt=0/0 end,cause=true,seen=2,at=false},
  {name='long cause with a valid clock time',edit=function(p)p.loadoutCause=HUGE end,cause=false,at=false},
  {name='original slot string',edit=function(p)p.originalSlot=HUGE end,cause=true,original='unreadable',seen=2},
  {name='original slot table',edit=function(p)p.originalSlot={1} end,cause=true,original='unreadable',seen=2},
  {name='original slot fractional',edit=function(p)p.originalSlot=1.5 end,cause=true,original='unreadable',seen=2},
 }
 for _,case in ipairs(CASES)do
  local H,M,A,O,src,slots=S.Build(S.CAUSES[1])
  M=S.Reload(H,function(row,state)case.edit(row);case.edit(state)end)
  S.Pass(H,M,A);S.Rechecks(H,M,2)
  local ok,view=pcall(Nexus.OrbRuntime.RecoveryView)
  check(ok and type(view)=='table',case.name..': the owner answers')
  check(view.loadoutSeenSlot==case.seen,case.name..': an invalid slot is not reported, no slot is reported for a cause that is not valid, and a valid one is kept: '..tostring(view.loadoutSeenSlot))
  if case.at==false then check(view.loadoutSeenAt==nil,case.name..': an invalid clock time is not reported') end
  check((view.loadoutCause=='SLOT_DIFFERS')==case.cause and (case.cause or view.loadoutCause==nil),case.name..': only an exact known cause name is reported: '..tostring(view.loadoutCause))
  if case.original then check(view.originalSlotState=='unreadable' and view.originalSlot==nil,case.name..': an unreadable original slot is named unreadable') end
  local line3=Line3()
  check(line3 and #line3<400 and not line3:find('[%z\1-\31]') and not line3:find('XXXXXXXXXX',1,true),case.name..': the line is bounded and clean: '..tostring(line3))
  if case.at==false then check(not line3:find('set at',1,true),case.name..': no time is printed for an invalid one: '..tostring(line3)) end
  check(Nexus.SupportReport.Summary():find('Orb action',1,true)~=nil,case.name..': the summary is still produced')
 end
end
-- The fields a hold adds to a receipt are exactly three small scalars. A receipt that a post-reload session
-- latched has the key set of the reported receipt (the fixture plus its GUID) and nothing else.
do
 local F=S.Shape()
 local H,M,A,O,src,slots=S.Build(S.CAUSES[1])
 local latched=S.Receipt()
 local function Keys(t,skip)
  local ks={};for k in pairs(t)do if not (skip and skip[k]) then ks[#ks+1]=k end end;table.sort(ks);return table.concat(ks,',')
 end
 local want={guid=true};for k in pairs(F.receipt)do want[k]=true end
 check(Keys(latched,{loadoutCause=true,loadoutObservedSlot=true,loadoutObservedAt=true})==Keys(want),
  'a hold latched after a reload has exactly the keys of the reported receipt, apart from the two annotations: '..Keys(latched))
 check(latched.restored==true and latched.refreshRequested==false,'a save made in a session that restored the receipt writes restored and refreshRequested')
 check(type(latched.loadoutCause)=='string' and #latched.loadoutCause<=24 and type(latched.loadoutObservedSlot)=='number' and type(latched.loadoutObservedAt)=='number',
  'the annotations are a short name and two whole numbers')
 -- A hold latched in the ORIGINAL session (before any reload) has no restored / refreshRequested keys.
 local H5,M5,A5,O5=S.Fresh()
 local source,slotsLive=S.SpendOfferNoChoice(H5,M5,A5,O5)
 H5.perks.serverActiveSlot=2;S.Pass(H5,M5,A5)
 local live=S.Receipt()
 check(live.loadoutCause=='SLOT_DIFFERS' and live.restored==nil and live.refreshRequested==nil,'a hold latched in the original session carries no restored / refreshRequested keys')
end

-- 4b. A poisoned owner answer cannot take the line away or fill it with raw bytes.
do
 local H,M,A,O,src,slots=S.Build(S.CAUSES[1])
 local runtime=Nexus.OrbRuntime;local real=runtime.RecoveryView
 local POISON='SENTINEL'..string.char(1)..string.char(10)..string.char(7)..'|cffff0000|r'..string.rep('Z',300)
 runtime.RecoveryView=function()return {pending=true,restored=true,state='PAUSED',recovery='PAUSED',gate='loadout',loadoutChanged=true,
  originalSlot=POISON,originalSlotState=POISON,slotNow=POISON,slotNowKnown=POISON,slotRead=POISON,loadoutCheck=POISON,loadoutCause=POISON,
  loadoutSeenSlot=POISON,offerRecorded=POISON,unmet=POISON} end
 local lines=Nexus.SupportReport.OrbLines()
 check(#lines>=2,'a poisoned answer still gives the Orb lines')
 for i,l in ipairs(lines)do
  check(#l<400 and not l:find('[%z\1-\31]') and not l:find(string.rep('Z',30),1,true) and not l:find('SENTINEL',1,true),'poisoned line '..i..' is bounded and carries no raw value: '..#l)
 end
 runtime.RecoveryView=function()return {pending=true,restored=true,state='PAUSED',recovery='PAUSED',gate='loadout',loadoutChanged=true,
  unmet={POISON,'loadout',string.rep('choice',100),{}},originalSlot=1e300,slotNow=-5,loadoutSeenSlot=2^53} end
 lines=Nexus.SupportReport.OrbLines()
 for i,l in ipairs(lines)do check(#l<400 and not l:find('[%z\1-\31]') and not l:find('SENTINEL',1,true),'poisoned list line '..i..' is bounded')end
 runtime.RecoveryView=real
end

-- 4c. The support line checks every number again, whatever the owner answers: a slot that is negative, fractional, huge, NaN,
-- infinite or not a number is never printed.
do
 local H,M,A,O,src,slots=S.Build(S.CAUSES[1])
 local runtime=Nexus.OrbRuntime;local real=runtime.RecoveryView
 local BAD={-5,1.5,1e300,2^53,0/0,1/0,-1/0,65536,'7',{7},true}
 for index,bad in ipairs(BAD)do
  runtime.RecoveryView=function()return {pending=true,restored=true,state='PAUSED',recovery='PAUSED',gate='loadout',loadoutChanged=true,
   originalSlot=bad,originalSlotState='recorded',slotRead=true,slotNow=bad,slotNowKnown=true,loadoutCheck='CHANGED',
   loadoutCause='SLOT_DIFFERS',loadoutSeenSlot=bad,loadoutSeenAt=bad,offerRecorded=true,unmet={'loadout','choice'}} end
  local line3=Nexus.SupportReport.OrbLines()[3]
  check(line3=='  original slot=unreadable; slot now=not reported (data received); check=changed; hold cause=slot differed (slot data received); offer recorded=yes; unmet in record=loadout,choice',
   'bad number '..index..' ('..tostring(bad)..'): never printed: '..tostring(line3))
 end
 -- the limits themselves are accepted
 for _,good in ipairs({0,1,101,65535})do
  runtime.RecoveryView=function()return {pending=true,restored=true,state='PAUSED',recovery='PAUSED',gate='loadout',loadoutChanged=true,
   originalSlot=good,originalSlotState='recorded',slotRead=true,slotNow=good,slotNowKnown=true,loadoutCheck='CHANGED',
   loadoutCause='SLOT_DIFFERS',loadoutSeenSlot=good,offerRecorded=true,unmet={'loadout'}} end
  local line3=Nexus.SupportReport.OrbLines()[3]
  Has(line3,'original slot='..good..'; slot now='..good..' (data received)','good slot '..good)
  Has(line3,'saw slot '..good,'good slot '..good)
 end
 runtime.RecoveryView=real
end

-- 4d. No clock, or a clock that raises: the hold and its cause are still recorded; no time is.
for _,mode in ipairs({'missing','raising','not a number','out of range'})do
 local H,M,A,O=S.Fresh();local src,slots=S.SpendOfferNoChoice(H,M,A,O)
 local realTime=time
 if mode=='missing' then time=nil elseif mode=='raising' then time=function()error('no clock') end
 elseif mode=='not a number' then time=function()return 'now' end else time=function()return 5 end end
 H.perks.serverActiveSlot=2;S.Pass(H,M,A)
 time=realTime
 local r=S.Receipt()
 check(r.loadoutChanged==true and r.loadoutCause=='SLOT_DIFFERS' and r.loadoutObservedSlot==2 and r.loadoutObservedAt==nil,'4d clock '..mode..': the hold and cause are recorded, no time')
 check(Nexus.OrbRuntime.RecoveryView().loadoutSeenAt==nil and not Line3():find('set at',1,true),'4d clock '..mode..': no time is shown')
 check(M.Status().state=='PAUSED' and M.Status().pending and not M.Resume(),'4d clock '..mode..': held as before')
end

-- 3d. A cause without a hold is never shown: an edited or damaged receipt that carries a cause, a seen slot and a time but no hold.
do
 local H,M,A,O=S.Fresh();local src,slots=S.SpendOfferNoChoice(H,M,A,O)
 M=S.Reload(H,function(row,state)
  row.loadoutCause='SLOT_DIFFERS';row.loadoutObservedSlot=2;row.loadoutObservedAt=1700000000
  state.loadoutCause='SLOT_DIFFERS';state.loadoutObservedSlot=2;state.loadoutObservedAt=1700000000
 end)
 S.Pass(H,M,A);S.Rechecks(H,M,2)
 local v=Nexus.OrbRuntime.RecoveryView()
 check(v.loadoutChanged==false and v.loadoutCheck=='SAME' and v.loadoutCause==nil and v.loadoutSeenSlot==nil and v.loadoutSeenAt==nil,'3d: no hold: no cause, no seen slot and no time are returned')
 local line3=Line3()
 check(line3:find('hold cause=none recorded',1,true) and not line3:find('saw slot',1,true) and not line3:find('set at',1,true),'3d: the line says none recorded: '..tostring(line3))
 -- the support line alone: an owner answer with no hold and a valid cause
 local runtime=Nexus.OrbRuntime;local real=runtime.RecoveryView
 runtime.RecoveryView=function()return {pending=true,restored=true,state='RECOVERY',recovery='OFFER_OPEN',loadoutChanged=false,originalSlotState='recorded',originalSlot=1,
  slotRead=true,slotNow=1,slotNowKnown=true,loadoutCheck='SAME',loadoutCause='SLOT_DIFFERS',loadoutSeenSlot=2,loadoutSeenAt=1700000000,offerRecorded=true,unmet={'choice'}} end
 local stub=Nexus.SupportReport.OrbLines()[3]
 check(stub and stub:find('hold cause=none recorded',1,true) and not stub:find('slot differed',1,true) and not stub:find('saw slot',1,true) and not stub:find('set at',1,true),
  '3d: the support line shows no cause for an owner answer without a hold: '..tostring(stub))
 runtime.RecoveryView=real
end

-- 3e. "Unmet in record" is the saved record alone. A live state (no slot data yet, another character, a different slot read) is not in it.
do
 local H,M,A,O=S.Fresh();S.SpendOfferNoChoice(H,M,A,O)
 M=S.Reload(H);H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=nil;S.Pass(H,M,A)
 local v=Nexus.OrbRuntime.RecoveryView()
 check(v.loadoutChanged==false and v.loadoutCheck=='UNKNOWN' and ListText(v.unmet)=='choice','3e: waiting for the slot data: only the choice is unmet in the record: '..ListText(v.unmet))
 local line3=Line3()
 check(line3:find('check=waiting',1,true) and line3:find('unmet in record=choice',1,true) and not line3:find('loadout-unknown',1,true),'3e: the wait is the check, not a record fact: '..tostring(line3))
end
do
 local H,M,A,O=S.Fresh();S.SpendOfferNoChoice(H,M,A,O)
 M=S.Reload(H,function(row,state)row.guid='another character';state.guid='another character' end)
 H.perks.serverActiveSlot=2;S.Pass(H,M,A)
 local v=Nexus.OrbRuntime.RecoveryView()
 check(v.loadoutChanged==false and v.loadoutCheck=='CHANGED' and ListText(v.unmet)=='choice','3e: another character and a different slot read: the record has no hold: '..ListText(v.unmet)..' / '..tostring(v.loadoutCheck))
end

-- 4e. The saved slot is bounded whatever the game pushes: only a whole number 0..65535 is written, and -0 is written as 0.
for _,bad in ipairs({1.5,'2',1e12,-1,0/0,65536})do
 local H,M,A,O=S.Fresh();S.SpendOfferNoChoice(H,M,A,O)
 M=S.Reload(H);S.Pass(H,M,A)
 H.perks.serverActiveSlot=bad;S.Pass(H,M,A)
 local r=S.Receipt()
 check(r.loadoutChanged==true and r.loadoutCause=='SLOT_DIFFERS' and r.loadoutObservedSlot==nil,'4e live slot '..tostring(bad)..': the hold and cause are saved, the slot is not: '..tostring(r.loadoutObservedSlot))
 check(Nexus.OrbRuntime.RecoveryView().slotNow==nil and Line3():find('slot now=not reported',1,true),'4e live slot '..tostring(bad)..': the read slot is not reported')
end
do
 local H,M,A,O=S.Fresh();S.SpendOfferNoChoice(H,M,A,O)
 M=S.Reload(H);S.Pass(H,M,A)
 H.perks.serverActiveSlot=-0.0;S.Pass(H,M,A)
 local r=S.Receipt()
 check(r.loadoutObservedSlot==0 and 1/r.loadoutObservedSlot>0,'4e: a live -0 is saved as 0')
 local v=Nexus.OrbRuntime.RecoveryView()
 check(v.slotNow==0 and 1/v.slotNow>0,'4e: the live -0 is returned as 0')
 check(Line3():find('saw slot 0',1,true) and Line3():find('slot now=0 (',1,true) and not Line3():find('-0',1,true),'4e: and shown as 0: '..tostring(Line3()))
end
do
 local H,M,A,O=S.Fresh();S.SpendOfferNoChoice(H,M,A,O)
 M=S.Reload(H,function(row,state)row.originalSlot=-0.0;state.originalSlot=-0.0 end)
 H.perks.serverActiveSlot=0;S.Pass(H,M,A)
 local v=Nexus.OrbRuntime.RecoveryView()
 check(v.originalSlot==0 and 1/v.originalSlot>0 and Line3():find('original slot=0;',1,true) and not Line3():find('-0',1,true),'4e: a saved -0 original slot is shown as 0: '..tostring(Line3()))
end

-- 4f. The owner's list is capped; a view with every gate set never leaks a raw value; -0 is shown as 0 by the line itself.
do
 local H,M,A,O,src,slots=S.Build(S.CAUSES[1])
 local runtime=Nexus.OrbRuntime;local real=runtime.RecoveryView
 local many={};for i=1,200 do many[i]='choice' end
 local function Gated(extra)
  local view={pending=true,restored=true,state='PAUSED',recovery='PAUSED',gate='loadout',loadoutChanged=true,originalSlotState='recorded',originalSlot=1,
   slotRead=true,slotNow=1,slotNowKnown=true,loadoutCheck='CHANGED',loadoutCause='SLOT_DIFFERS',loadoutSeenSlot=2,offerRecorded=true,unmet={'loadout'}}
  for k,v in pairs(extra)do view[k]=v end
  runtime.RecoveryView=function()return view end
  return Nexus.SupportReport.OrbLines()
 end
 local lines=Gated({unmet=many})
 check(lines[3] and lines[3]:match('unmet in record=([^;]*)$')=='choice,choice,choice' and #lines[3]<400,'4f: a list of 200 entries shows at most three: '..tostring(lines[3]))
 local POISON='SENTINEL'..string.char(1)..string.char(10)..string.char(7)..string.rep('Z',300)
 local VIEWS={
  {originalSlot=POISON},{slotNow=POISON},{loadoutSeenSlot=POISON,loadoutSeenAt=POISON},{originalSlotState=POISON},{loadoutCheck=POISON},{unmet={POISON,'loadout'}},
 }
 for index,extra in ipairs(VIEWS)do
  lines=Gated(extra)
  check(#lines==3,'4f view '..index..': three lines, not the fallback answer: '..#lines)
  for i,l in ipairs(lines)do
   check(#l<400 and not l:find('[%z\1-\31]') and not l:find('SENTINEL',1,true) and not l:find('ZZZZZZZZZZ',1,true),'4f view '..index..' line '..i..' is bounded and carries no raw value')
  end
 end
 lines=Gated({originalSlot=-0.0,slotNow=-0.0,loadoutSeenSlot=-0.0})
 check(lines[3]:find('original slot=0; slot now=0 (',1,true) and lines[3]:find('saw slot 0',1,true) and not lines[3]:find('-0',1,true),'4f: the line itself shows -0 as 0: '..tostring(lines[3]))
 runtime.RecoveryView=real
end

-- 5. Nothing about what the code does changed: the hold, every refusal and the game
-- calls are those of the characterization test, with the diagnostics in place.
for _,cause in ipairs(S.CAUSES)do
 local H,M,A,O,src,slots=S.Build(cause)
 local calls=S.CountCalls(H)
 S.Rechecks(H,M,3);M.Stop();S.Rechecks(H,M,2)
 M=S.Reload(H);H.perks.serverActiveSlot=cause.expect.original or 1;H.perks.serverBuildSlots=slots;S.Pass(H,M,A);S.Rechecks(H,M,3)
 check(M.Status().pending and not M.Resume() and not M.Prepare() and M.BlocksOrdinary()==true,cause.name..': held, refused and blocked as before')
 check(calls.spend==0 and calls.select==0 and H.Count('orb-spend')==1 and H.Count('take')==0,cause.name..': no call reached the game from Nexus')
end
-- 6. The real receipt shape (orb_loadout_hold_shape): original slot 101 recorded, offer recorded, no choice,
-- a hold with no recorded cause.
do
 local F=S.Shape();local OFFER=S.Offer(F)
 -- early: the receipt is loaded and the game has not been read yet
 do
  local H,M,A,O=S.World(F,{slot=102,charges=0})
  local v=Nexus.OrbRuntime.RecoveryView()
  check(v.loadoutChanged==true and v.originalSlot==101 and v.originalSlotState=='recorded','shape early: hold and original slot 101 shown before the first read')
  check(v.slotRead==false and v.loadoutCheck==nil and v.slotNow==nil,'shape early: no slot read yet, nothing guessed')
  check(Line3()=='  original slot=101; slot now=unread; check=unread; hold cause=not recorded; offer recorded=yes; unmet in record=loadout,choice',
   'shape early: third line: '..tostring(Line3()))
 end
 -- ready, slot 102 with data: the reported state
 do
  local H,M,A,O=S.World(F,{slot=102,charges=0})
  S.Pass(H,M,A);S.Rechecks(H,M,2)
  local v=Nexus.OrbRuntime.RecoveryView()
  check(v.originalSlot==101 and v.slotNow==102 and v.slotNowKnown==true and v.loadoutCheck=='CHANGED','shape: original 101, now 102 with data, changed')
  check(v.loadoutCause==nil and v.loadoutSeenSlot==nil,'shape: the old hold carries no recorded cause; slot 102 is not turned into one')
  check(v.offerRecorded==true and ListText(v.unmet)=='loadout,choice','shape: offer recorded; loadout and choice unmet')
  check(Line3()=='  original slot=101; slot now=102 (data received); check=changed; hold cause=not recorded; offer recorded=yes; unmet in record=loadout,choice',
   'shape: third line: '..tostring(Line3()))
  local p=S.Receipt()
  check(p.loadoutCause==nil and p.loadoutObservedSlot==nil and p.originalSlot==101,'shape: nothing was written into the old receipt')
  -- back at slot 101: still held, still unrecorded, and the live check says so
  H.perks.serverActiveSlot=101;S.Pass(H,M,A);S.Rechecks(H,M,3)
  v=Nexus.OrbRuntime.RecoveryView()
  check(v.loadoutCheck=='CHANGED' and v.loadoutCause==nil and S.Receipt().loadoutCause==nil,'shape: at the original slot the latch still reads changed and no cause appears')
 end
 -- a client with no slot-data capability and the default slot
 do
  local H,M,A,O=S.World(F,{slot=0,noCapability=true,charges=0})
  S.Pass(H,M,A);S.Rechecks(H,M,2)
  check(Line3()=='  original slot=101; slot now=0 (client reports no slot data); check=changed; hold cause=not recorded; offer recorded=yes; unmet in record=loadout,choice',
   'shape no capability: third line: '..tostring(Line3()))
 end
 -- the same receipt without the hold, offer open: only the choice is unmet
 do
  local H,M,A,O=S.World(F,{slot=101,latch=false,charges=F.receipt.chargesBefore-1,open=true})
  S.Pass(H,M,A);S.Rechecks(H,M,2)
  local v=Nexus.OrbRuntime.RecoveryView()
  check(v.loadoutChanged==false and v.loadoutCheck=='SAME' and ListText(v.unmet)=='choice' and v.recovery=='OFFER_OPEN','shape unlatched: same loadout, only the choice unmet')
  check(Line3()=='  original slot=101; slot now=101 (data received); check=same; hold cause=none recorded; offer recorded=yes; unmet in record=choice',
   'shape unlatched: third line: '..tostring(Line3()))
 end
 -- a recorded choice with the hold: only the loadout is unmet
 do
  local pick=OFFER[3]
  local H,M,A,O=S.World(F,{slot=101,charges=0,gain=pick,choice=pick})
  S.Pass(H,M,A);S.Rechecks(H,M,3)
  local v=Nexus.OrbRuntime.RecoveryView()
  check(v.choiceObserved==true and v.selectedKey==pick and ListText(v.unmet)=='loadout','shape recorded choice: only the loadout is unmet')
 end
end
print('PASS Orb loadout hold diagnostics: original slot, live slot, hold cause (recorded once, never inferred), unmet requirements; bounded and validated checks='..checks)
