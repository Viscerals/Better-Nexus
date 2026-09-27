-- Two reported Orb recovery holds, driven through the real OrbRuntime and
-- OrbAdapter with synthetic services. Nothing here spends, chooses, refunds or
-- erases on the player's behalf; every scenario counts the calls that reach
-- the game.
--
-- A. After a reload (or login) the client keeps GetServerBuildSlots() nil and
-- its active slot at the load-time default 0 ("none") until the server sends
-- its build-slot data (client perks_service). A restored receipt must not
-- read that default as a loadout change: it waits, read-only, and settles from
-- the exact result once the real slot is known. A real different slot, and a
-- receipt without an original slot, still keep the hold. No run starts before
-- the slot is known (the assignment waits for the same data).
--
-- B. A restored receipt with choice evidence waits in WAIT_RESULT. The status
-- names the settlement requirement that is not met, so it does not promise
-- that a fresh ownership response settles a hold that something else keeps.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Fresh()
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonhold=nil
 local H=dofile('tests/prototype/orbs_support.lua')
 return H,H.M,H.A,H.O
end
local function Reload(H,saved)
 H.Fire('PLAYER_LOGOUT')
 if saved then saved() end -- the saved data as the next load reads it
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:Hide() end
 assert(loadfile('core/OrbAdapter.lua'))('Nexus',{})
 assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
 return Nexus.OrbRuntime
end
local function Receipt()return Nexus.Store.State().orbRefinement.pending end
local function Loadouts(H,A)
 H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
  [2]={name='Two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 assert(A.SetLoadoutWishlistIdentity(1,'First',{{spellId=410002,quality=2,stacks=2}}))
end
local function Result(H,source,extra)
 local out=H.Clone(H.granted);local removed=false
 for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
 assert(removed);out['Desired A']={{spellId=410002,quality=2}}
 if extra then out['Desired B']={{spellId=410004,quality=3}} end
 H.granted=out
end
-- One spend and one automatic choice on loadout 1; the server applies the
-- choice (or not) and the client reloads before Nexus settles it.
local function SpendThenReload(H,M,A,O,applied)
 Loadouts(H,A)
 assert(M.Start(3));H.Offer()
 assert(H.Count('orb-spend')==1 and H.Count('take')==1,'setup: one spend and one automatic choice')
 local source=O.source
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 if applied then Result(H,source) end
 local slots=H.perks.serverBuildSlots
 local receipt=Receipt()
 M=Reload(H)
 return M,source,slots,receipt
end
local function Rechecks(H,M,n)for _=1,n or 3 do H.now=H.now+4;M.Recheck();M.Pump();H.Advance(.5)end end

-- A1. Slot data not received after the reload: wait, then settle from the
-- exact result once the real slot is known.
do
 local H,M,A,O=Fresh()
 local source,slots,before
 H.perks.serverBuildSlots=nil -- prepared below by Loadouts; reset at reload
 M,source,slots,before=SpendThenReload(H,M,A,O,false)
 check(before.originalSlot==1,'A1 setup: the receipt records the real slot 1')
 H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=nil -- client load-time defaults
 H.Notify();A.Poll();H.Advance(.5)
 local s=M.Status()
 check(s.state=='RECOVERY' and s.recovery and s.recovery.kind=='LOADOUT_UNKNOWN',
  'A1: before the slot data, recovery waits for it: '..tostring(s.state)..'/'..tostring(s.recovery and s.recovery.kind))
 check(Receipt().loadoutChanged==nil,'A: a load-time default slot is not recorded as a loadout change')
 check(s.reason:find('active build slot',1,true)~=nil,'A1: the status says it waits for the active build slot: '..s.reason)
 check(M.BlocksOrdinary()==true,'A1: ordinary rolling stays blocked while the action is unresolved')
 check(tostring(A.OrbBlockReason('Ordinary rolling')):find('unresolved after a reload',1,true)~=nil,
  'A1: the block says the action is still being observed, not that it cannot be confirmed: '..tostring(A.OrbBlockReason('Ordinary rolling')))
 check(not M.Resume() and not M.Prepare(),'A1: no Resume and no new run while unresolved')
 local snapshot=H.Clone(Receipt())
 Rechecks(H,M,2)
 check(H.Count('orb-spend')==1 and H.Count('take')==1,'A1: repeated Recheck sends nothing')
 check(Receipt().loadoutChanged==nil and Receipt().originalSlot==snapshot.originalSlot
  and Receipt().selectedKey==snapshot.selectedKey,'A1: repeated Recheck keeps the receipt')
 H.perks.serverActiveSlot=1;H.Notify();A.Poll();H.Advance(.5)
 check(M.Status().recovery.kind=='LOADOUT_UNKNOWN','A1: an active-slot push without the build-slot data still waits')
 H.perks.serverBuildSlots=slots;H.Notify();A.Poll();H.Advance(.5)
 check(M.Status().pending and M.Status().recovery.kind=='WAIT_RESULT','A1: known slot 1: waiting for the result')
 Result(H,source);H.Notify();A.Poll();H.Advance(.5);Rechecks(H,M,2)
 s=M.Status()
 check(s.state=='STOPPED' and not s.pending and s.spent==1 and s.reserved==0,
  'A: the exact result settles the action once the real slot is known: '..tostring(s.state)..' '..tostring(s.reason))
 Rechecks(H,M,2)
 check(M.Status().spent==1 and H.Count('orb-spend')==1 and H.Count('take')==1,'A1: settled once; nothing else sent')
end

-- A1b. The exact result is already applied when the client loads, and fresh
-- ownership responses arrive while the slot is still unknown: nothing settles
-- until the real slot is known.
do
 local H,M,A,O=Fresh()
 local source,slots
 M,source,slots=SpendThenReload(H,M,A,O,true)
 H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=nil;H.Notify();A.Poll();H.Advance(.5)
 Rechecks(H,M,3)
 check(M.Status().pending and M.Status().recovery.kind=='LOADOUT_UNKNOWN' and Receipt().loadoutChanged==nil,
  'A: nothing settles while the slot is unknown, even with the exact result and fresh responses')
 H.perks.serverActiveSlot=1;H.perks.serverBuildSlots=slots;H.Notify();A.Poll();H.Advance(.5);Rechecks(H,M,2)
 check(M.Status().state=='STOPPED' and not M.Status().pending and M.Status().spent==1,
  'A1b: once slot 1 is known the exact result settles: '..tostring(M.Status().reason))
 check(H.Count('orb-spend')==1 and H.Count('take')==1,'A1b: nothing else sent')
end

-- A2. The slot data arrives and shows another loadout: that is a real change;
-- the hold stays, including after a return to the original slot.
do
 local H,M,A,O=Fresh()
 local source,slots
 M,source,slots=SpendThenReload(H,M,A,O,false)
 H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=nil;H.Notify();A.Poll();H.Advance(.5)
 H.perks.serverActiveSlot=2;H.perks.serverBuildSlots=slots;H.Notify();A.Poll();H.Advance(.5)
 check(Receipt().loadoutChanged==true,'A2: a known different slot is recorded as a loadout change')
 check(M.Status().reason:find('original loadout',1,true)~=nil,'A2: the loadout hold is reported')
 H.perks.serverActiveSlot=1;H.Notify();A.Poll();Result(H,source);H.Notify();A.Poll();H.Advance(.5);Rechecks(H,M,2)
 check(M.Status().pending and M.Status().spent+M.Status().reserved==1 and not M.Resume(),
  'A2: returning to the original slot does not settle it; exposure kept')
 check(H.Count('orb-spend')==1 and H.Count('take')==1,'A2: nothing else sent')
end

-- A3. A receipt without an original slot (an older build) keeps the hold even
-- when the slot data is known.
do
 local H,M,A,O=Fresh()
 local source
 Loadouts(H,A)
 assert(M.Start(3));H.Offer()
 source=O.source
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 M=Reload(H,function()
  local row=NexusDB.chars[Nexus.Store.CurrentOwnerKey()]
  assert(row.orbRefinement.pending.originalSlot==1);row.orbRefinement.pending.originalSlot=nil
 end)
 Result(H,source);H.Notify();A.Poll();H.Advance(.5);Rechecks(H,M,2)
 check(M.Status().pending and Receipt().loadoutChanged==true and M.Status().reason:find('original loadout',1,true)~=nil,
  'A3: a receipt without an original slot keeps the loadout hold')
end

-- A4 (preservation). Right after login, before the slot data, the assignment
-- itself is not resolved (A.Slots() needs the same build-slot data), so no
-- Orb run can start and no receipt can record the default slot.
do
 local H,M,A,O=Fresh()
 H.OrbPlan()
 H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=nil;H.Notify();A.Poll()
 local ok,why=M.Start(3)
 check(not ok and M.Status().canStart==false and H.Count('orb-spend')==0,
  'A4: no Orb run starts before the build-slot data: '..tostring(why))
 H.perks.serverBuildSlots={};H.Notify();A.Poll()
 ok,why=M.Start(3)
 check(ok==true and Receipt().originalSlot==0,'A4: once the slot data is known the run starts and records the reported slot: '..tostring(why))
end

-- B. WAIT_RESULT names the unmet requirement. Each case keeps the hold and
-- sends nothing; the control settles.
local CASES={
 {name='control'},
 {name='income',gate='charges',text='the Orb balance is 10 and the record requires 9'},
 {name='board',gate='board',text='an Echo choice is open in the game'},
 {name='noreply',gate='fresh',text='Recheck requests one'},
 {name='notyet',gate='ownership',text='does not show the chosen Echo yet'},
}
for _,case in ipairs(CASES)do
 local H,M,A,O=Fresh()
 H.OrbPlan();H.Approve(2,false);H.Offer()
 assert(H.Count('orb-spend')==1 and H.Count('take')==1,'B setup: one spend and one automatic choice')
 local source=O.source
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 local out=H.Clone(H.granted);local removed=false
 for _,es in pairs(out)do for i=#es,1,-1 do if not removed and es[i].spellId==source then table.remove(es,i);removed=true end end end
 assert(removed);if case.name~='notyet' then out['Desired A']={{spellId=410002,quality=2}} end
 H.granted=out
 if case.name=='income' then O.charges=O.charges+1 end
 if case.name=='noreply' then H.holdGrantedResponse=true end
 M=Reload(H)
 if case.name=='board' then H.Board({{spellId=410005,quality=0},{spellId=410006,quality=3},{spellId=410008,quality=1}}) end
 H.Notify();A.Poll();H.Advance(.5);Rechecks(H,M,3)
 local s=M.Status()
 if case.name=='control' then
  check(s.state=='STOPPED' and not s.pending and s.spent==1,'B control: the exact result settles: '..tostring(s.reason))
 else
  check(s.state=='RECOVERY' and s.pending and s.recovery.kind=='WAIT_RESULT','B '..case.name..': the hold stays in WAIT_RESULT')
  check(s.recovery.gate and s.recovery.gate.gate==case.gate,
   'B '..case.name..': the status names the unmet requirement: '..tostring(s.recovery.gate and s.recovery.gate.gate))
  check(s.reason:find(case.text,1,true)~=nil,'B '..case.name..': the reason says it: '..s.reason)
  check(case.gate=='fresh' or s.reason:find('fresh ownership response',1,true)==nil,
   'B '..case.name..': it does not promise that a fresh response settles it')
  check(M.BlocksOrdinary()==true and s.spent+s.reserved==1,'B '..case.name..': block and exposure kept')
 end
 check(H.Count('orb-spend')==1 and H.Count('take')==1,'B '..case.name..': nothing else sent')
end
print('PASS Orb recovery: a load-time default slot waits instead of blocking for good; WAIT_RESULT names the unmet requirement checks='..checks)
