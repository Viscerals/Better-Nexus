-- W3 characterization: a legacy Saved Build assignment is "upgraded" only in a detached snapshot.
--
-- Two old record shapes survive in saved data: a bare designed-slot number (1.0.5) and a table with
-- a slot but no content key. GameAdapter's ResolveAssociation recognizes each on its first validated
-- contact and assigns `links[slot] = {slot,key,name}` / `saved.key, saved.name = ...` on the table it
-- read from Store.State(). Store.State() returns a DETACHED copy, so those assignments never reach
-- authoritative state: after the next authorized write invalidates the snapshot, and after a
-- serialized reload, the durable record is the legacy shape again. A slot reused by another Wishlist
-- then resolves to that Wishlist, which is exactly what the persisted identity was meant to prevent.
--
-- This test states what is true TODAY (EXPECT below) and the invariants any correction must keep.
-- Authoritative state is read from the saved table (NexusDB) after owner writes and after a
-- serialize / reload round trip, never from the in-memory snapshot alone. If the upgrade is later
-- persisted at a sanctioned owner boundary, flip EXPECT (the comments name which lines change).
local F=dofile('tests/prototype/format5_support.lua')
local checks=0
local function check(ok,msg) checks=checks+1; assert(ok,msg) end
local EXPECT={
 durableUpgraded=false, -- after resolution + an unrelated authorized write, is the durable record upgraded?
 followsReusedSlot=true, -- does the legacy association resolve to Wishlist B once slot 101 holds B?
}
local function plan(id) return {{spellId=id,quality=id%4,stacks=1,locked=false}} end
local A_ID,B_ID=200003,200004
local function slots(name,id)
 return {[1]={name='Owned one',verified=true,echoes=plan(200001)},[101]={name=name,verified=false,echoes=plan(id)}}
end
local function boot(saved,serverSlots)
 Nexus=nil;SlashCmdList=nil;WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua')
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots=serverSlots
 NexusDB=saved
 H.Boot()
 return H
end
local function owner() return Nexus.MainInternals.StoreAuthorityOwner end
-- The authoritative record of Saved Build 1: the saved table itself.
local function durable()
 for _,r in pairs(NexusDB.chars or {}) do
  if type(r)=='table' and type(r.loadoutWishlists)=='table' then return r.loadoutWishlists[1] end
 end
end
local function targetSpell()
 local w=Nexus.GameAdapter.Wishlist()
 return w and w.entries and w.entries[1] and w.entries[1].spellId or nil
end
local function unrelatedAuthorizedWrite()
 check(owner().UpdateStateV1(function(s) s.recordedPicks=s.recordedPicks or {};s.recordedPicks[200001]=1 end),'an unrelated authorized write is accepted')
end
local function isLegacy(shape,v)
 if shape=='number' then return type(v)=='number' end
 return type(v)=='table' and (v.key==nil or v.key=='') and v.slot==101
end

for _,shape in ipairs({'number','keyless table'}) do
 local H=boot(nil,slots('Plan A',A_ID))
 local A=Nexus.GameAdapter
 check(owner().UpdateStateV1(function(s)
  s.loadoutWishlists=shape=='number' and {[1]=101} or {[1]={slot=101,name='Plan A'}}
 end),shape..': the legacy record is written through the owner')
 check(isLegacy(shape,durable()),shape..': the saved table holds the legacy shape')

 -- Invariant: the read-only diagnosis and the Journal getter do not rewrite saved data.
 local before=F.Serialize(NexusDB)
 A.GetLoadoutWishlistState(1);A.GetLoadoutWishlist(1)
 check(F.Serialize(NexusDB)==before,shape..': the getters leave the saved table byte-identical')
 -- The active-slot projection resolves A through the legacy record.
 check(targetSpell()==A_ID,shape..': the legacy record resolves to Wishlist A')
 -- The snapshot shows the upgrade; the saved table does not.
 local snap=Nexus.Store.State().loadoutWishlists[1]
 check(type(snap)=='table' and snap.key~=nil,shape..': the detached snapshot carries the content key')
 check(isLegacy(shape,durable()),shape..': the saved table is still the legacy shape after resolution')
 -- An unrelated authorized write invalidates the snapshot: the upgrade is gone from it too.
 unrelatedAuthorizedWrite()
 local after=Nexus.Store.State().loadoutWishlists[1]
 check(EXPECT.durableUpgraded==(not isLegacy(shape,durable())),shape..': saved record after an unrelated write: '..tostring(durable()))
 check(EXPECT.durableUpgraded==(type(after)=='table' and after.key~=nil),shape..': the snapshot after invalidation')
 local saved=F.Serialize(NexusDB)

 -- Slot 101 is reused by Wishlist B in the same session.
 H.perks.serverBuildSlots[101]={name='Plan B',verified=false,echoes=plan(B_ID)};H.Notify();A.Poll()
 check((targetSpell()==B_ID)==EXPECT.followsReusedSlot,shape..': same session, slot reused by B: target '..tostring(targetSpell()))
 -- A later session reads the serialized saved table, with slot 101 holding B.
 H=boot(assert(loadstring('return '..saved))(),slots('Plan B',B_ID))
 check((targetSpell()==B_ID)==EXPECT.followsReusedSlot,shape..': later session, slot is B: target '..tostring(targetSpell()))
 check(EXPECT.durableUpgraded==(not isLegacy(shape,durable())),shape..': the saved record in the later session')
end

-- Contrast: an association made by an explicit action carries its identity in the saved table, and a
-- reused slot does not capture it.
do
 local H=boot(nil,slots('Plan A',A_ID))
 local A=Nexus.GameAdapter
 local chosen;for _,c in ipairs(A.GetWishlistCandidates()) do if c.slot==101 then chosen=c end end
 check(A.SetLoadoutWishlist(1,101,chosen),'an explicit assignment is made')
 local record=durable()
 check(type(record)=='table' and record.key and record.assignmentId,'the saved record carries a content key and an assignment id')
 unrelatedAuthorizedWrite()
 local saved=F.Serialize(NexusDB)
 H=boot(assert(loadstring('return '..saved))(),slots('Plan B',B_ID))
 check(targetSpell()~=B_ID,'after a reload, a reused slot does not capture an explicitly assigned Wishlist')
 check(type(durable())=='table' and durable().key==record.key,'and the saved record is unchanged')
 -- Unassign removes a record in whatever shape it holds.
 check(Nexus.GameAdapter.ClearLoadoutWishlist(1),'unassign')
 check(durable()==nil,'the saved table no longer holds an association for Saved Build 1')
end

-- A legacy record is replaced by an explicit assignment and cleared by Unassign (existing semantics).
do
 local H=boot(nil,slots('Plan A',A_ID))
 local A=Nexus.GameAdapter
 check(owner().UpdateStateV1(function(s) s.loadoutWishlists={[1]=101} end),'legacy number written')
 check(A.ClearLoadoutWishlist(1),'unassign of a legacy record')
 check(durable()==nil,'the legacy record is removed from the saved table')
end

print('PASS legacy_assignment_snapshot: '..checks..' checks (legacy number and keyless table; durable state after invalidation and reload; slot reuse; explicit-assignment contrast; unassign)')
