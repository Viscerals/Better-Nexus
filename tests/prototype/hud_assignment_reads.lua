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

-- 8. One candidate list per assignment read (2026-10-03). The candidate list
-- (LiveWishlistCandidates) builds, normalizes and hashes every designed
-- mirror. With a server mirror as the assignment, one read built it twice:
-- once to find the mirror, once more for the mirror note. It is now built at
-- most once per read, shared only inside that read and dropped on return, so
-- every read still sees the slots, mirrors and association of its own moment.
-- Builds are counted by a call hook on the real function; a hook cannot see
-- calls made by a compiled LuaJIT trace, so the count runs interpreted.
local function Builds(fn)
 if jit then jit.off();jit.flush() end
 local n=0
 debug.sethook(function()
  local info=debug.getinfo(2,'n')
  if info and info.name=='LiveWishlistCandidates' then n=n+1 end
 end,'c')
 local ok,result=pcall(fn)
 debug.sethook()
 if jit then jit.on() end
 assert(ok,result)
 return n,result
end
local function ReadBuilds(label,want)
 local w0=writes
 local n,r=Builds(function() return A.AssignedWishlist() end)
 check(n==want,label..': candidate builds in one assignment read (was 2 with a server mirror): '..n)
 check(writes==w0,label..': the read enters no Store mutation')
 return r
end
local function Mirror(slot,name,spell)
 P.serverBuildSlots[slot]={name=name,verified=false,echoes={{spellId=spell,quality=0,stacks=1,locked=false}}}
end
local function Pick(slot)
 for _,c in ipairs(A.GetWishlistCandidates()) do if c.slot==slot then return c end end
end
-- The mirror note of an assignment whose plan has no distinct server mirror
-- (gone, edited, or not unique): its exact saved plan is retained.
local ABSENT='Assigned Wishlist is absent from the current server list. Its saved plan is retained. Refresh the list or reassign deliberately.'
local NO_MIRROR='Assigned Wishlist has no distinct current server mirror. Its exact saved plan is retained. Refresh the list or reassign deliberately.'

Mirror(101,'Server plan',200004)
check(A.SetLoadoutWishlist(1,101,Pick(101)),'fixture: server Wishlist associated again')
a=ReadBuilds('server mirror listed',1)
check(a.state=='ready' and a.name=='Server plan' and a.mirrorNote==nil and #a.entries==1 and a.entries[1].spellId==200004,
 'server mirror listed: ready, no mirror note')
local firstRead=a
a=ReadBuilds('server mirror listed again',1)
check(a.state==firstRead.state and a.key==firstRead.key and a.identity==firstRead.identity and a.mirrorNote==nil
 and a~=firstRead and a.entries~=firstRead.entries and a.wishlist~=firstRead.wishlist,'stable reads agree and each returns new tables')
-- A caller that edits what one read returned cannot change the next read.
a.entries[1].stacks=99;a.wishlist.entries[1].stacks=99
a=ReadBuilds('after the caller edited a result',1)
check(a.entries[1].stacks==1 and a.wishlist.entries[1].stacks==1,'results are detached: the next read is not the edited one')

-- The HUD preparation makes one read, so one build, also when its display
-- input changes and the view model is rebuilt.
local n=Builds(function() return Nexus.RefreshHudView() end)
check(n==1,'one candidate build per stable HUD preparation (was 2): '..n)
local rawNotice=Nexus.Updates.GetVisibleNotice
local noticeText
Nexus.Updates.GetVisibleNotice=function() return {text=noticeText} end
for i=1,3 do
 noticeText='display change '..i
 n=Builds(function() return Nexus.RefreshHudView() end)
 check(n==1,'one candidate build per changed-display HUD preparation '..i..' (was 2): '..n)
end
Nexus.Updates.GetVisibleNotice=rawNotice
shown=Nexus.Panel._lastModel and Nexus.Panel._lastModel.assignment
a=A.AssignedWishlist()
check(shown and shown.state==a.state and shown.note==a.note and shown.name==a.name and shown.emptySlot==a.emptySlot,
 'the HUD shows the fields of a fresh assignment read')

-- A mirror that disappears, reappears, or changes inside the same slot table
-- is seen by the very next read (no list survives a read).
local mirror=P.serverBuildSlots[101]
P.serverBuildSlots[101]=nil
a=ReadBuilds('mirror gone',1)
check(a.state=='ready' and a.entries[1].spellId==200004 and a.mirrorNote==NO_MIRROR,'mirror gone: saved plan kept, no distinct mirror explained: '..tostring(a.mirrorNote))
P.serverBuildSlots[101]=mirror
a=ReadBuilds('mirror back',1)
check(a.state=='ready' and a.mirrorNote==nil,'mirror back: no mirror note: '..tostring(a.mirrorNote))
mirror.echoes[1].stacks=2
a=ReadBuilds('mirror edited in place',1)
check(a.state=='ready' and a.entries[1].stacks==1 and a.mirrorNote==NO_MIRROR,
 'same-table edit is seen: the saved plan stays and no distinct mirror remains: '..tostring(a.mirrorNote))
mirror.echoes[1].stacks=1
a=ReadBuilds('mirror edited back',1)
check(a.mirrorNote==nil,'same-table edit back is seen: '..tostring(a.mirrorNote))

-- Two equal-content mirrors, neither named like the assignment: exact
-- content and name cannot pick one, so the plan has no distinct mirror.
P.serverBuildSlots[101].name='Mirror A'
Mirror(102,'Mirror B',200004)
a=ReadBuilds('ambiguous mirrors',1)
check(a.state=='ready' and a.entries[1].spellId==200004 and a.mirrorNote==NO_MIRROR,'ambiguous mirrors: '..tostring(a.mirrorNote))
P.serverBuildSlots[101].name='Server plan'
P.serverBuildSlots[102]=nil
a=ReadBuilds('mirror named again',1)
check(a.mirrorNote==nil,'unique named mirror again: '..tostring(a.mirrorNote))

-- A legacy record with a slot and no content key: the mirror check is the
-- step that explains it, so this is the only state whose note comes from the
-- second use of the candidate list.
check(owner.UpdateStateV1(function(s) s.loadoutWishlists[1]={slot=101,name='Legacy plan'} end),'fixture: keyless legacy record')
a=ReadBuilds('keyless record, mirror listed',1)
check(a.state=='ready' and a.entries[1].spellId==200004 and a.mirrorNote==ABSENT,'keyless record: mirror check note: '..tostring(a.mirrorNote))

-- First run, no Saved Build in use: a server mirror as the first-run plan.
A.ClearLoadoutWishlist(1)
P.serverActiveSlot=0
check(A.SetFirstRunWishlist(101,Pick(101)),'fixture: first-run server Wishlist')
a=ReadBuilds('first run, mirror listed',1)
check(a.state=='ready' and a.name=='Server plan' and a.note=='First-run wishlist target' and a.mirrorNote==nil,
 'first run, mirror listed: '..tostring(a.state)..' '..tostring(a.note)..' '..tostring(a.mirrorNote))
mirror=P.serverBuildSlots[101]
P.serverBuildSlots[101]=nil
a=ReadBuilds('first run, mirror gone',1)
check(a.state=='ready' and a.entries[1].spellId==200004 and a.mirrorNote==NO_MIRROR,'first run, mirror gone: '..tostring(a.mirrorNote))
P.serverBuildSlots[101]=mirror
-- The one hand-off a read may make: a populated active Saved Build with no
-- assignment takes the first-run plan. It is still made, with one build.
P.serverActiveSlot=1
local w0=writes
local nHand,hand=Builds(function() return A.AssignedWishlist() end)
check(nHand==1,'first-run hand-off read: candidate builds (was 2): '..nHand)
check(hand.state=='ready' and hand.name=='Server plan' and hand.mirrorNote==nil and writes>w0,
 'first-run hand-off read: ready, and the hand-off is stored: '..tostring(hand.state)..' '..(writes-w0))
a=ReadBuilds('after the hand-off',1)
check(a.state=='ready' and a.name=='Server plan' and a.mirrorNote==nil,'after the hand-off: the stored assignment is read')
A.ClearLoadoutWishlist(1)
check(A.ClearFirstRunWishlist(),'fixture: first-run Wishlist cleared')

print('PASS assigned Wishlist reads read the slots once and enter no Store mutation; '..checks..' checks')
