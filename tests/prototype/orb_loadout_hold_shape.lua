-- The actual pending-receipt SHAPE of the reported test.9072 hold, reproduced with a
-- synthetic fixture (orb_loadout_hold_shape_support.lua: deterministic renumbering of
-- the spell ids; counts, quality and key equality kept; no name, GUID or account).
-- Real Store, OrbRuntime, OrbAdapter, GameAdapter and SupportReport; only the game
-- services are synthetic.
--
-- The receipt: an original slot (a designed Wishlist slot, 101) IS recorded; the offer
-- (three cards) and the one-Orb spend were recorded in the original session; NO selection
-- or choice field exists at all; a loadout hold is latched, with no recorded cause.
--
-- A. The two reported states, from that receipt alone: the early start-up state
--    (RECOVERY / CHECKING, game pick unknown) and the ready state (PAUSED / PAUSED,
--    waiting for the loadout). Neither return to the original slot nor Recheck, Stop or
--    a reload changes it.
-- B. What the receipt can and cannot prove. The same receipt WITHOUT the hold is also
--    unsettled: it records no choice. With its offer still open, the normal read-only
--    recovery waits for the player's own pick in the game's offer window, records it, and
--    only then can an exact fresh result settle it. With its offer gone, no ownership
--    result, however exact, settles it (the three offered Echoes are each tried). Adding a
--    recorded choice makes the same world settle, and adding the hold back stops it again.
--    So the missing choice, not the balance, the counters or the Wishlist, is the
--    evidence that is absent.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local S=dofile('tests/prototype/orb_loadout_hold_support.lua')
local F=S.Shape()
check(F.keys==72 and F.copies==79 and F.locked==6 and F.offered==3,'fixture: 72 keys, 79 copies, 6 locked entries, 3 offered cards')
do
 local keys,copies=0,0
 for _,n in pairs(F.receipt.before)do keys=keys+1;copies=copies+n end
 check(keys==72 and copies==79 and F.receipt.before[F.receipt.removed]~=nil,'fixture: the before map and the source are intact')
end

local SOURCE=F.receipt.removed
local OFFER=S.Offer(F)
check(#OFFER==3,'fixture: three offered cards in board order')
local IdQ,OwnedMap=S.IdQ,function(H,gain,keepSource)return S.OwnedMap(F,H,gain,keepSource)end
local Slots=S.Slots
local function World(opts)return S.World(F,opts)end
local function Pass(H,M,A,n)for _=1,n or 1 do S.Pass(H,M,A) end S.Rechecks(H,M,2)end
local function View()return Nexus.OrbRuntime.RecoveryView()end
local function Lines()return Nexus.SupportReport.OrbLines()end

-- A1. The early start-up report: the receipt is loaded and the game is not read yet.
do
 local H,M,A,O=World({slot=102,charges=0})
 local lines=Lines()
 check(lines[1]=='Orb action: unresolved after a reload; state=RECOVERY; recovery=CHECKING; waiting for=none','A1: early first line: '..tostring(lines[1]))
 check(lines[2]=='  spend confirmed=yes; choice=none; selected=none; source='..SOURCE..'; game pick in flight=unknown; loadout change recorded=yes; automatic refresh=not requested',
  'A1: early second line: '..tostring(lines[2]))
 check(View().loadoutChanged==true and Nexus.Store.State().orbRefinement.pending.originalSlot==101,'A1: the hold and the recorded original slot 101 are in the receipt before the first read')
 check(M.Status().limit==219 and M.Status().spent==170 and M.Status().reserved==0,'A1: the counters are the receipt\'s own (170 of 219)')
end

-- A2. The ready state, for each way the slot can be seen afterwards: always the reported hold.
local READY={
 {name='slot 102 with slot data',slot=102,known=true},
 {name='slot 101 with slot data (the original slot)',slot=101,known=true},
 {name='default slot 0 with slot data',slot=0,known=true},
 {name='client with no slot-data capability, slot 0',slot=0,noCapability=true},
}
for _,case in ipairs(READY)do
 local H,M,A,O=World({slot=case.slot,known=case.known,noCapability=case.noCapability,charges=0})
 local calls=S.CountCalls(H)
 Pass(H,M,A,2)
 local lines=Lines()
 -- 101 is the recorded original slot: with slot data it is the SAME loadout, and the receipt's own latch still holds.
 check(lines[1]=='Orb action: unresolved after a reload; state=PAUSED; recovery=PAUSED; waiting for=loadout','A2 '..case.name..': ready first line: '..tostring(lines[1]))
 check(lines[2]=='  spend confirmed=yes; choice=none; selected=none; source='..SOURCE..'; game pick in flight=no; loadout change recorded=yes; automatic refresh=not requested',
  'A2 '..case.name..': ready second line: '..tostring(lines[2]))
 check(not M.Resume() and not M.Prepare() and M.BlocksOrdinary()==true,'A2 '..case.name..': no Resume, no new run, ordinary rolling blocked')
 -- a return to slot 101, a Recheck, a Stop and a reload do not change it
 H.perks.serverActiveSlot=101;H.perks.serverBuildSlots=Slots();Pass(H,M,A,2)
 M.Stop();Pass(H,M,A,1)
 M=S.Reload(H);H.perks.serverActiveSlot=101;H.perks.serverBuildSlots=Slots();Pass(H,M,A,2)
 local again=Lines()
 check(again[1]==lines[1] and again[2]==lines[2] and View().loadoutChanged==true and M.Status().pending,'A2 '..case.name..': slot 101, Recheck, Stop and a reload do not clear it')
 check(calls.spend==0 and calls.select==0 and H.Count('orb-spend')==0 and H.Count('take')==0,'A2 '..case.name..': nothing reached the game')
end

-- B1. The same receipt WITHOUT the hold, offer still open, loadout verified: the normal recovery waits
-- for the player's own pick. Nexus never chooses. The recorded pick and an exact fresh result settle it.
do
 local H,M,A,O=World({slot=101,latch=false,charges=F.receipt.chargesBefore-1,open=true})
 local calls=S.CountCalls(H)
 Pass(H,M,A,2)
 local v=View()
 check(v.loadoutChanged==false and v.recovery=='OFFER_OPEN' and v.state=='RECOVERY' and v.gate=='choice','B1: unlatched, the open offer is waited for and the choice is the unmet requirement: '..tostring(v.recovery)..'/'..tostring(v.gate))
 check(not M.Resume() and calls.select==0 and calls.spend==0,'B1: Nexus chooses and spends nothing')
 local pick=OFFER[2];local id,q=IdQ(pick)
 check(calls.pick(id)==true,'B1: the player chooses in the offer window');H.Advance(.5)
 local p=Nexus.Store.State().orbRefinement.pending
 check(p.selectedKey==pick and p.choiceObserved==true and p.selectionAttempted==true,'B1: the choice is recorded from the player\'s own pick')
 H.granted=OwnedMap(H,pick);H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;O.offer=false
 S.Pass(H,M,A);S.Rechecks(H,M,3)
 check(M.Status().state=='STOPPED' and not M.Status().pending and M.Status().spent==170,'B1: the exact fresh result settles the recorded choice: '..tostring(M.Status().reason))
 check(calls.spend==0 and calls.select==1 and calls.player==1,'B1: only the player\'s pick reached the game')
end

-- B2. Same receipt without the hold, offer gone: no result settles it, whichever offered card the world shows.
for _,gain in ipairs(OFFER)do
 local H,M,A,O=World({slot=101,latch=false,charges=0,gain=gain})
 local calls=S.CountCalls(H)
 Pass(H,M,A,2);S.Rechecks(H,M,3)
 local v=View()
 check(v.pending==true and v.state=='RECOVERY' and v.recovery=='UNOBSERVABLE','B2 '..gain..': an exact result without a recorded choice is not settlement: '..tostring(v.state)..'/'..tostring(v.recovery))
 check(v.selectedKey==nil and not Nexus.Store.State().orbRefinement.pending.selectedKey,'B2 '..gain..': no selection is inferred from the result')
 check(M.Status().spent==170 and calls.spend==0 and calls.select==0,'B2 '..gain..': spend kept, nothing sent')
end
-- B2b. Charges equal to the receipt's balance after the spend, ownership as before: wait for a possible offer.
do
 local H,M,A,O=World({slot=101,latch=false,charges=F.receipt.chargesBefore-1})
 Pass(H,M,A,2)
 check(View().recovery=='WAIT_OFFER' and View().pending==true,'B2b: balance one less, ownership as recorded, no offer: waits for a possible offer')
end

-- B3. A recorded choice (an offered card) with no hold settles on an exact fresh result; with the hold it does not.
for _,latch in ipairs({false,true})do
 local pick=OFFER[3]
 local H,M,A,O=World({slot=101,latch=latch,charges=0,gain=pick,choice=pick})
 Pass(H,M,A,2);S.Rechecks(H,M,3)
 if latch then
  check(M.Status().pending and View().loadoutChanged==true and View().state=='PAUSED' and View().gate=='loadout',
   'B3 with the hold: even a recorded choice and the exact result do not settle; the loadout is the unmet requirement')
 else
  check(not M.Status().pending and M.Status().state=='STOPPED','B3 without the hold: a recorded offered choice and the exact fresh result settle: '..tostring(M.Status().reason))
 end
end

print('PASS Orb loadout hold shape: the reported receipt is held by the loadout and also records no choice; settlement needs a recorded choice checks='..checks)
