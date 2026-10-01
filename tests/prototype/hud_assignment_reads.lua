-- Assigned Wishlist read (HUD and lifecycle cost, 2026-10-01, test.9053).
-- Measured on the reporter's saved data (756 builds): every HUD preparation
-- reads the assigned Wishlist through GameAdapter.AssignedWishlist. On
-- test.9053 that read built the server slot projection three times (itself,
-- Wishlist, and the association lookup) and read the character row through
-- the Store mutation entry, which compares the whole row with the read
-- snapshot (about 415 tables and 58 KB a call). The HUD keeps three fields.
--
-- Required: one read reads the server slots once and enters no Store
-- mutation, in every assignment state below; one HUD preparation makes one
-- such read and shows its state, note and name; each state gives the same
-- result fields as before; a change between two reads (active slot, slot
-- data, association) is seen by the next read.
local H=dofile('tests/prototype/harness.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local P,S=H.perks,H.service
local plan={{spellId=200001,quality=1,stacks=2},{spellId=200002,quality=2,stacks=1},{spellId=200003,quality=3,stacks=1}}
P.serverBuildSlots={[1]={name='Saved one',verified=true,echoes=H.Clone(plan)},
 [2]={name='Saved two',verified=true,echoes={{spellId=200010,quality=2,stacks=1}}}}
P.serverActiveSlot=1
H.Boot()
local A=Nexus.GameAdapter

local slotReads,writes=0,0
local rawSlots=S.GetServerBuildSlots
S.GetServerBuildSlots=function(...) slotReads=slotReads+1;return rawSlots(...) end
local owner=Nexus.MainInternals.StoreAuthorityOwner
local rawUpdate=owner.UpdateStateV1
owner.UpdateStateV1=function(...) writes=writes+1;return rawUpdate(...) end

-- One read, with the work it did.
local function Read(label)
 local s0,w0=slotReads,writes
 local a=A.AssignedWishlist()
 local reads,entries=slotReads-s0,writes-w0
 check(reads<=1,label..': one server slot read per assignment read (test.9053: two or three): '..reads)
 check(entries==0,label..': the read enters no Store mutation (test.9053: one): '..entries)
 return a
end

-- 1. Populated active loadout, no association.
local a=Read('unassigned')
check(a.state=='unassigned' and a.activeSlot==1 and a.name==nil,'unassigned: state '..tostring(a.state))
check(a.note=='Loadout 1 has no wishlist association. Set it in the Echo Journal.','unassigned: note '..tostring(a.note))

-- 2. Associated with the active loadout.
check(A.SetLoadoutWishlistIdentity(1,'Slot plan',H.Clone(plan)),'fixture: association set')
a=Read('ready')
check(a.state=='ready' and a.name=='Slot plan' and a.activeSlot==1,'ready: state '..tostring(a.state)..' '..tostring(a.name))
check(type(a.entries)=='table' and #a.entries==3,'ready: the three plan rows')
for i,e in ipairs(plan) do
 local r=a.entries[i]
 check(r and r.spellId==e.spellId and r.quality==e.quality and r.stacks==e.stacks and r.locked==false,'ready: row '..i)
end
check(a.key==A.WishlistKey(a.entries) and type(a.identity)=='string' and a.identity~='','ready: identity '..tostring(a.identity))
check(a.owner==Nexus.Store.CurrentOwnerKey(),'ready: owner')
local again=Read('ready again')
check(again.state==a.state and again.key==a.key and again.identity==a.identity and again.name==a.name
 and again.note==a.note and again.mirrorNote==a.mirrorNote,'two reads of one state agree')
check(again~=a and again.entries~=a.entries,'each read returns new tables')

-- 3. The HUD: one assignment read per preparation, and its fields are shown.
local hudReads,hudSlotReads,hudWrites=0,0,0
local rawAssigned=A.AssignedWishlist
A.AssignedWishlist=function(...)
 hudReads=hudReads+1
 local s0,w0=slotReads,writes
 local r=rawAssigned(...)
 hudSlotReads,hudWrites=hudSlotReads+slotReads-s0,hudWrites+writes-w0
 return r
end
check(Nexus.RefreshHudView()~=false,'the HUD refreshes')
A.AssignedWishlist=rawAssigned
check(hudReads==1,'one assignment read per HUD preparation: '..hudReads)
check(hudSlotReads==1 and hudWrites==0,'the HUD read: one slot read, no Store mutation (test.9053: 3 and 1): '..hudSlotReads..' '..hudWrites)
local shown=Nexus.Panel._lastModel and Nexus.Panel._lastModel.assignment
check(type(shown)=='table' and shown.state=='ready' and shown.name=='Slot plan' and shown.note==a.note,
 'the HUD shows the read state and name: '..tostring(shown and shown.state))

-- 4. A change between two reads is seen by the next read.
P.serverActiveSlot=2
a=Read('other loadout')
check(a.state=='unassigned' and a.activeSlot==2
 and a.note=='Loadout 2 has no wishlist association. Set it in the Echo Journal.','active slot change is seen: '..tostring(a.note))
P.serverActiveSlot=1
check(Read('back').state=='ready','active slot restored is seen')
check(A.SetLoadoutWishlistIdentity(1,'Renamed plan',H.Clone(plan)),'fixture: association replaced')
check(Read('renamed').name=='Renamed plan','association change is seen')
-- A server Wishlist (designed slot) as the association; then the server list
-- drops it. The read uses the slot data of this call for the mirror check.
P.serverBuildSlots[101]={name='Server plan',verified=false,echoes={{spellId=200004,quality=0,stacks=1,locked=false}}}
local chosen;for _,c in ipairs(A.GetWishlistCandidates()) do if c.slot==101 then chosen=c end end
check(chosen and A.SetLoadoutWishlist(1,101,chosen),'fixture: server Wishlist associated')
a=Read('server Wishlist')
check(a.state=='ready' and a.entries[1].spellId==200004 and a.mirrorNote==nil,'server Wishlist: listed, no mirror note')
P.serverBuildSlots[101]=nil
a=Read('server Wishlist gone')
check(a.state=='ready' and a.entries[1].spellId==200004 and type(a.mirrorNote)=='string',
 'slot data change is seen: the saved plan stays and the absence is explained: '..tostring(a.mirrorNote))
check(A.SetLoadoutWishlistIdentity(1,'Slot plan',H.Clone(plan)),'fixture: slot plan again')

-- 5. Active slot not known yet: restoring, from the saved association.
P.serverActiveSlot=nil
a=Read('restoring')
check(a.state=='restoring','unknown active slot with a saved association: '..tostring(a.state))
P.serverActiveSlot=1

-- 6. No server slot data at all.
local savedSlots=P.serverBuildSlots
P.serverBuildSlots=nil
local s0,w0=slotReads,writes
a=A.AssignedWishlist()
check(a.state=='restoring' and writes==w0,'no slot data: restoring, no Store mutation: '..tostring(a.state))
-- With no projection to pass, Wishlist reads the slots itself (as before).
check(slotReads-s0<=2,'no slot data: at most two slot reads: '..(slotReads-s0))
P.serverBuildSlots=savedSlots

-- 7. First run: no active Saved Build, a first-run Wishlist.
P.serverActiveSlot=0
check(A.SetFirstRunWishlistIdentity('Starter plan',H.Clone(plan)),'fixture: first-run Wishlist set')
a=Read('first run')
check(a.state=='ready' and a.name=='Starter plan' and a.note=='First-run wishlist target','first run: '..tostring(a.state)..' '..tostring(a.note))
P.serverActiveSlot=1

print('PASS assigned Wishlist reads read the slots once and enter no Store mutation; '..checks..' checks')
