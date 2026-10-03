-- History and compatibility of the Orb loadout hold. The released test.9049 runtime
-- (tests/prototype/fixtures/released_9049) is used as a real OLDER build, with the
-- current game services of the harness.
--
-- 1. An older build latched the hold on a plain reload: after a reload the client keeps a
--    load-time default slot until the server sends its build-slot data, and the older
--    build read that default as a loadout change and saved the hold. The current build
--    waits instead. A hold that an older build saved is therefore NOT evidence of a
--    change, and it looks exactly like a real one: no later read can tell them apart.
-- 2. The current build does not relabel such a hold: it shows the cause as not recorded.
-- 3. Compatibility of the two saved annotation fields: an older build copies unknown
--    fields of a pending receipt through its own re-save, and holds on a receipt that
--    carries them exactly as it holds on one that does not.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local S=dofile('tests/prototype/orb_loadout_hold_support.lua')
local OLD='tests/prototype/fixtures/released_9049/core/'
local function Read(path)local f=assert(io.open(path,'rb'));local t=f:read('*a');f:close();return t end
-- Vacuity guard: the fixture really is the older rule (no wait for the build-slot data).
check(not Read(OLD..'OrbRuntime.lua'):find('LOADOUT_UNKNOWN',1,true) and Read(OLD..'OrbRuntime.lua'):find('loadoutChanged',1,true),
 'the fixture runtime is the older rule: it has the hold and no wait for the build-slot data')
local function ReloadOld(H,saved)
 H.Fire('PLAYER_LOGOUT')
 if saved then saved(NexusDB.chars[Nexus.Store.CurrentOwnerKey()].orbRefinement.pending,Nexus.Store.State().orbRefinement.pending) end
 if NexusOrbRuntime then NexusOrbRuntime:SetScript('OnUpdate',nil);NexusOrbRuntime:SetScript('OnEvent',nil);NexusOrbRuntime:Hide() end
 H.perks.pendingSelectSpellId=nil
 assert(loadfile(OLD..'OrbAdapter.lua'))('Nexus',{})
 assert(loadfile(OLD..'OrbRuntime.lua'))('Nexus',{})
 return Nexus.OrbRuntime
end
local function Default(H)H.perks.serverActiveSlot=0;H.perks.serverBuildSlots=nil end

-- 1. A plain reload: the older build saves the hold, the current build waits.
do
 local H,M,A,O=S.Fresh();S.SpendOfferNoChoice(H,M,A,O)
 M=ReloadOld(H);Default(H);S.Pass(H,M,A);S.Rechecks(H,M,2)
 check(S.Receipt().loadoutChanged==true and M.Status().state=='PAUSED','1: the older build saved a hold on a plain reload (no slot change happened)')
 check(S.Receipt().originalSlot==1 and S.Receipt().spendConfirmed==true and S.Receipt().selectedKey==nil,'1: the older build left the rest of the receipt as it was')
end
do
 local H,M,A,O=S.Fresh();S.SpendOfferNoChoice(H,M,A,O)
 M=S.Reload(H);Default(H);S.Pass(H,M,A);S.Rechecks(H,M,2)
 check(S.Receipt().loadoutChanged==nil and Nexus.OrbRuntime.RecoveryView().recovery=='LOADOUT_UNKNOWN','1: the current build waits for the slot data and saves no hold')
end

-- 2. A hold saved by the older build is shown by the current build with its cause not recorded,
-- and is the same hold as a real change in every other way the owner can show.
do
 local H,M,A,O=S.Fresh();local src,slots=S.SpendOfferNoChoice(H,M,A,O)
 M=ReloadOld(H);Default(H);S.Pass(H,M,A)
 check(S.Receipt().loadoutChanged==true,'2 setup: the older build saved a hold')
 -- the current runtime now loads on the same saved receipt, at the original slot with slot data
 M=S.Reload(H);H.perks.serverActiveSlot=1;H.perks.serverBuildSlots=slots;S.Pass(H,M,A);S.Rechecks(H,M,3)
 local v=Nexus.OrbRuntime.RecoveryView()
 check(v.loadoutChanged==true and v.loadoutCause==nil and v.loadoutSeenSlot==nil,'2: the current build shows no cause for a hold an older build saved')
 check(v.slotNow==1 and v.slotNowKnown==true and v.originalSlot==1 and v.state=='PAUSED' and v.gate=='loadout',
  '2: the player is at the original slot with slot data, and the hold is still there; it is the reported view')
 local line=Nexus.SupportReport.OrbLines()[3]
 check(line and line:find('hold cause=not recorded',1,true) and line:find('original slot=1; slot now=1 (data received); check=changed',1,true),'2: the support line says so: '..tostring(line))
 check(S.Receipt().loadoutCause==nil and S.Receipt().loadoutObservedSlot==nil,'2: nothing was added to the receipt after the fact')
 check(not M.Resume() and not M.Prepare() and M.BlocksOrdinary()==true,'2: the hold still holds')
end

-- 3. Compatibility of the annotation fields with an older build.
do
 local H,M,A,O=S.Fresh();S.SpendOfferNoChoice(H,M,A,O)
 -- a pending receipt as this build writes it, carrying the annotation, not yet held
 M=ReloadOld(H,function(row,state)
  row.loadoutCause='SLOT_DIFFERS';row.loadoutObservedSlot=2;state.loadoutCause='SLOT_DIFFERS';state.loadoutObservedSlot=2
 end)
 Default(H);S.Pass(H,M,A)
 local r=S.Receipt()
 check(r.loadoutChanged==true and r.loadoutCause=='SLOT_DIFFERS' and r.loadoutObservedSlot==2,'3: an older build keeps the annotation fields through its own re-save')
 check(NexusDB.chars[Nexus.Store.CurrentOwnerKey()].orbRefinement.pending.loadoutCause=='SLOT_DIFFERS','3: the saved row keeps them too')
end
do
 -- a hold this build wrote, loaded by an older build: held exactly as before
 local H,M,A,O,src,slots=S.Build(S.CAUSES[1])
 check(S.Receipt().loadoutCause=='SLOT_DIFFERS','3 setup: this build wrote the annotation with the hold')
 M=ReloadOld(H);H.perks.serverActiveSlot=1;H.perks.serverBuildSlots=slots;S.Pass(H,M,A);S.Rechecks(H,M,3)
 check(M.Status().state=='PAUSED' and M.Status().pending and not M.Resume() and S.Receipt().loadoutChanged==true,'3: an older build holds on a receipt that carries the annotation, as on one without it')
 check(H.Count('orb-spend')==1 and H.Count('take')==0,'3: nothing reached the game')
end
print('PASS Orb loadout hold history: an older build saved the hold on a plain reload; the cause of such a hold stays unrecorded; the annotation is compatible with an older build checks='..checks)
