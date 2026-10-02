-- W3: a legacy Saved Build assignment must reach authoritative state, not only a detached snapshot.
--
-- Two old record shapes survive in saved data: a bare designed-slot number (1.0.5) and a table with
-- a slot but no content key. ResolveAssociation used to "upgrade" them by assigning to the table it
-- read from Store.State(), a DETACHED copy: the identity never reached saved data, an authorized write
-- or a reload brought the legacy shape back, and a slot reused by another Wishlist then captured the
-- association. ResolveAssociation now only recognizes them; ReconcileLegacyAssignments (run from the
-- poll, like ReconcileTomePending) persists the identity through the state owner.
--
-- Authoritative state is read from the saved table (NexusDB) after owner writes, after the poll, and
-- after a serialize / reload round trip, never from the in-memory snapshot alone.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0
local function check(ok,msg) checks=checks+1; assert(ok,msg) end
local function plan(id) return {{spellId=id,quality=id%4,stacks=1,locked=false}} end
local A_ID,B_ID=200003,200004
local A_KEY,B_KEY='200003:1','200004:1'
local function slots(name,id)
 local s={[1]={name='Owned one',verified=true,echoes=plan(200001)}}
 if name then s[101]={name=name,verified=false,echoes=plan(id)} end
 return s
end
local H
local function boot(saved,serverSlots)
 Nexus=nil;SlashCmdList=nil;WishlistRealizerDB=nil
 H=dofile('tests/prototype/harness.lua')
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots=serverSlots
 NexusDB=saved
 H.Boot()
 return H
end
local function owner() return Nexus.MainInternals.StoreAuthorityOwner end
-- The authoritative record of a Saved Build: the saved table itself (one character row here).
local function row()
 local found,n
 n=0
 for _,r in pairs(NexusDB.chars or {}) do
  if type(r)=='table' and type(r.loadoutWishlists)=='table' then found=r;n=n+1 end
 end
 check(n==1,'exactly one saved row holds assignments')
 return found
end
local function durable(index) return row().loadoutWishlists[index or 1] end
local function targetSpell()
 local w=Nexus.GameAdapter.Wishlist()
 return w and w.entries and w.entries[1] and w.entries[1].spellId or nil
end
local function unrelatedAuthorizedWrite()
 check(owner().UpdateStateV1(function(s) s.recordedPicks=s.recordedPicks or {};s.recordedPicks[200001]=1 end),'an unrelated authorized write is accepted')
end
local function seed(shape,index,slot)
 check(owner().UpdateStateV1(function(s)
  s.loadoutWishlists=s.loadoutWishlists or {}
  s.loadoutWishlists[index]=shape=='number' and slot or {slot=slot,name='Plan A',note='kept'}
 end),shape..': the legacy record is written through the owner')
end
local function upgraded(shape,v)
 return type(v)=='table' and v.key==A_KEY and v.name=='Plan A' and v.slot==101 and v.assignmentId==nil
  and (shape=='number' or v.note=='kept')
end

for _,shape in ipairs({'number','keyless table'}) do
 boot(nil,slots('Plan A',A_ID))
 local A=Nexus.GameAdapter
 seed(shape,1,101)
 check(shape=='number' and durable()==101 or type(durable())=='table' and durable().key==nil,shape..': the saved table holds the legacy shape')

 -- Reads never write: the getters, the diagnosis and the active-slot projection leave saved data alone.
 local before=F.Serialize(NexusDB)
 A.GetLoadoutWishlistState(1);A.GetLoadoutWishlist(1);A.GetLoadoutCandidates()
 check(targetSpell()==A_ID,shape..': the legacy record resolves to Wishlist A')
 check(A.AssignedWishlist().state=='ready',shape..': and the HUD read shows it ready')
 check(F.Serialize(NexusDB)==before,shape..': no read changed the saved table')

 -- The poll persists the identity through the owner: the saved table, then the snapshot, then a reload.
 H.Advance(1)
 check(upgraded(shape,durable()),shape..': the saved table now holds the content identity of Wishlist A')
 local snap=Nexus.Store.State().loadoutWishlists[1]
 check(upgraded(shape,snap),shape..': and so does the snapshot')
 unrelatedAuthorizedWrite()
 check(upgraded(shape,durable()),shape..': an unrelated authorized write does not undo it')
 check(upgraded(shape,Nexus.Store.State().loadoutWishlists[1]),shape..': nor does the invalidated snapshot')
 local saved=F.Serialize(NexusDB)

 -- Slot 101 is reused by Wishlist B in the same session: the association keeps Wishlist A.
 H.perks.serverBuildSlots[101]={name='Plan B',verified=false,echoes=plan(B_ID)};H.Notify();H.Advance(1)
 check(targetSpell()==A_ID,shape..': same session, slot reused by B: the target stays A, got '..tostring(targetSpell()))
 check(upgraded(shape,durable()),shape..': the saved record is still A')
 -- A later session reads the serialized saved table, with slot 101 holding B.
 boot(assert(loadstring('return '..saved))(),slots('Plan B',B_ID))
 H.Advance(1)
 check(targetSpell()==A_ID,shape..': later session, slot is B: the target stays A, got '..tostring(targetSpell()))
 check(upgraded(shape,durable()),shape..': the saved record in the later session is still A')
 check(durable().key~=B_KEY,shape..': and never B')
end

-- Legacy data on disk before the session, slot not shown yet: nothing is upgraded without validation.
do
 boot(nil,slots(nil))
 seed('number',1,101)
 local saved=F.Serialize(NexusDB)
 boot(assert(loadstring('return '..saved))(),slots(nil))
 H.Advance(2)
 check(durable()==101,'no Wishlist at slot 101 yet: the legacy record is left as it is')
 H.perks.serverBuildSlots[101]={name='Plan A',verified=false,echoes=plan(A_ID)};H.Notify();H.Advance(1)
 check(upgraded('number',durable()),'once the mirror shows the slot, the identity is persisted')
end

-- Only what the mirror validates is upgraded; other records are left alone.
do
 boot(nil,slots('Plan A',A_ID))
 seed('number',1,101)
 seed('number',2,102) -- slot 102 shows nothing
 check(owner().UpdateStateV1(function(s) s.loadoutWishlists[3]={slot=103,key='200090:1',name='Modern',assignmentId='assigned:7'} end),'a modern record is present')
 H.Advance(1)
 check(upgraded('number',durable(1)),'the validated record is upgraded')
 check(durable(2)==102,'a record with no Wishlist at its slot stays legacy')
 local modern=durable(3)
 check(modern.key=='200090:1' and modern.assignmentId=='assigned:7' and modern.name=='Modern','a modern record is untouched')
end

-- The mirror is unknown at first (no slot table), then appears WITHOUT a notification: the attempt that
-- found no mirror was not counted, so the next poll upgrades.
do
 boot(nil,nil)
 seed('number',1,101)
 H.Advance(2)
 check(durable()==101,'with no slot table the legacy record is left as it is')
 H.perks.serverBuildSlots=slots('Plan A',A_ID)
 H.Advance(1)
 check(upgraded('number',durable()),'the first poll that sees the mirror persists the identity')
end

-- A legacy record that appears after the first upgrade, at an unchanged mirror (Restore of a retained
-- keyless table), is tried at once and not only after the mirror next changes.
do
 boot(nil,slots('Plan A',A_ID))
 seed('number',1,101)
 H.Advance(1)
 check(upgraded('number',durable()),'the first record is upgraded')
 H.perks.serverBuildSlots[102]={name='Plan C',verified=false,echoes=plan(200011)}
 H.Notify();H.Advance(1)
 check(owner().UpdateStateV1(function(s) s.loadoutWishlists[2]={slot=102,name='Plan C'} end),'a legacy keyless record appears later')
 H.Advance(1) -- no notification, no change of the mirror
 local late=durable(2)
 check(late.key=='200011:1' and late.slot==102,'it is upgraded without waiting for the mirror to change: '..tostring(late.key))
end

-- An open editor's assignment token for the Saved Build, and the assignment actions, survive the upgrade.
for _,shape in ipairs({'number','keyless table'}) do
 boot(nil,slots('Plan A',A_ID))
 local A=Nexus.GameAdapter
 seed(shape,1,101)
 local token=A.LoadoutAssignmentToken(1)
 local bound=A.AssignmentActionSnapshot()
 H.Advance(1)
 check(upgraded(shape,durable()),shape..': the record is upgraded')
 check(A.LoadoutAssignmentToken(1)==token,shape..': the binding token of the Saved Build is unchanged by the upgrade: '..tostring(token))
 check(A.AssignmentActionUnchanged(bound,1)==true,shape..': an editor bound before the upgrade still finds its assignment action unchanged')
end

-- A legacy record that appears while another stays unvalidated is tried at once, even though an attempt was
-- already counted at this mirror generation.
do
 boot(nil,slots('Plan A',A_ID))
 seed('number',2,105) -- no Wishlist at slot 105
 H.Advance(2)
 check(durable(2)==105,'the unvalidated record stays legacy')
 seed('number',1,101)
 H.Advance(1) -- no notification, no change of the mirror
 check(upgraded('number',durable(1)),'a second legacy record is upgraded without waiting for the mirror to change')
 check(durable(2)==105,'and the first stays legacy')
end

-- The same legacy record coming back after none existed (Unassign, then an older removal restored) is tried again.
do
 boot(nil,slots('Plan A',A_ID))
 seed('keyless table',1,101)
 H.Advance(1)
 check(upgraded('keyless table',durable()),'the record is upgraded')
 check(Nexus.GameAdapter.ClearLoadoutWishlist(1),'unassign')
 H.Advance(2) -- no legacy record: the attempt state is cleared
 seed('keyless table',1,101)
 H.Advance(1) -- same mirror generation, same record
 check(upgraded('keyless table',durable()),'the identical legacy record returning is upgraded again')
end

-- Positive control for the poll-cost check below: the upgrade's transaction is recognized by its `plan`
-- upvalue, so a legacy record must enter it exactly once.
do
 boot(nil,slots('Plan A',A_ID))
 seed('number',1,101)
 local raw=owner().UpdateStateV1
 local entered=0
 owner().UpdateStateV1=function(mutator,...)
  local i=1
  while true do
   local name=debug.getupvalue(mutator,i)
   if not name then break end
   if name=='plan' then entered=entered+1 end
   i=i+1
  end
  return raw(mutator,...)
 end
 H.Advance(3)
 owner().UpdateStateV1=raw
 check(entered==1,'a legacy record enters the upgrade transaction exactly once: '..entered)
end

-- The passive-diagnostic write block holds the upgrade back; lifting it lets the poll persist it.
do
 boot(nil,slots('Plan A',A_ID))
 seed('number',1,101)
 Nexus.GameAdapter.DIAGNOSTIC_PASSIVE=true
 H.Advance(2)
 check(durable()==101,'under the passive-diagnostic write block the saved table is not written')
 Nexus.GameAdapter.DIAGNOSTIC_PASSIVE=nil
 H.Notify();H.Advance(1)
 check(upgraded('number',durable()),'once the block is lifted the identity is persisted')
end

-- A table that carries its own contents (a plan saved before content keys) keeps them: it is not a bare
-- slot reference, and the live row at its slot is not its identity.
do
 boot(nil,slots('Plan A',A_ID))
 check(owner().UpdateStateV1(function(s)
  s.loadoutWishlists={[1]={slot=101,name='Own plan',echoes=plan(B_ID),assignmentId='assigned:6',designTargets={}}}
 end),'a keyless plan with its own contents is written through the owner')
 H.Advance(2)
 local kept=durable()
 check(kept.key==nil and kept.name=='Own plan' and kept.assignmentId=='assigned:6' and kept.echoes[1].spellId==B_ID,'it is left exactly as it was although slot 101 shows another Wishlist')
end

-- A newer explicit choice made between the read and the write is never overwritten.
do
 boot(nil,slots('Plan A',A_ID))
 seed('keyless table',1,101)
 local raw=owner().UpdateStateV1
 local fired=0
 owner().UpdateStateV1=function(mutator)
  if fired==0 and type(durable())=='table' and durable().key==nil then
   fired=1
   raw(function(s) s.loadoutWishlists[1]={slot=101,key='200090:2',name='Explicit choice',assignmentId='assigned:99'} end)
  end
  return raw(mutator)
 end
 H.Advance(1)
 owner().UpdateStateV1=raw
 check(fired==1,'the explicit choice was made inside the upgrade window')
 local current=durable()
 check(current.key=='200090:2' and current.name=='Explicit choice' and current.assignmentId=='assigned:99','the explicit choice is kept, not overwritten by the upgrade')
end

-- No legacy shape, no work: the poll never enters the mutation entry for it.
do
 boot(nil,slots('Plan A',A_ID))
 local A=Nexus.GameAdapter
 local chosen;for _,c in ipairs(A.GetWishlistCandidates()) do if c.slot==101 then chosen=c end end
 check(A.SetLoadoutWishlist(1,101,chosen),'an explicit assignment is made')
 local record=durable()
 check(type(record)=='table' and record.key and record.assignmentId,'the saved record carries a content key and an assignment id')
 -- Other startup writes exist; the upgrade's own transaction is recognized by its `plan` upvalue.
 local raw=owner().UpdateStateV1
 local entered=0
 owner().UpdateStateV1=function(mutator,...)
  local i=1
  while true do
   local name=debug.getupvalue(mutator,i)
   if not name then break end
   if name=='plan' then entered=entered+1 end
   i=i+1
  end
  return raw(mutator,...)
 end
 H.Advance(3);H.Notify();H.Advance(1)
 owner().UpdateStateV1=raw
 check(entered==0,'a profile with no legacy record never enters the mutation entry for the upgrade: '..entered)
 -- the explicit assignment is not captured by a reused slot after a reload
 unrelatedAuthorizedWrite()
 local saved=F.Serialize(NexusDB)
 boot(assert(loadstring('return '..saved))(),slots('Plan B',B_ID))
 H.Advance(1)
 check(targetSpell()==A_ID,'after a reload, a reused slot does not capture an explicitly assigned Wishlist')
 check(durable().key==record.key and durable().assignmentId==record.assignmentId,'and the saved record is unchanged')
 -- Unassign removes the record; Restore brings back the record as it was saved.
 check(Nexus.GameAdapter.ClearLoadoutWishlist(1),'unassign')
 check(durable()==nil,'the saved table no longer holds an association for Saved Build 1')
end

-- Unassign then Restore of an upgraded legacy record returns the identity, not the old shape.
do
 boot(nil,slots('Plan A',A_ID))
 seed('keyless table',1,101)
 H.Advance(1)
 check(upgraded('keyless table',durable()),'the keyless record is upgraded')
 check(Nexus.GameAdapter.ClearLoadoutWishlist(1),'unassign')
 check(durable()==nil,'the association is removed')
 check(Nexus.GameAdapter.RestoreForgottenWishlistPlan(),'restore')
 local back=durable()
 check(type(back)=='table' and back.key==A_KEY,'the restored record keeps the content identity: '..tostring(back and back.key))
end

-- A slot row the adapter could only partly read is not evidence: its readable entries are not the row.
-- The legacy record stays as it was (no inferred identity); the complete row, when it arrives, is retried
-- and persisted, and survives an authorized write and a serialize / reload.
local COMPLETE_KEY='200003:1,200011:1'
local function rowOf(entries) return {name='Plan A',verified=false,echoes=entries} end
local function upgradeTransaction(mutator)
 local i=1
 while true do
  local name=debug.getupvalue(mutator,i)
  if not name then return false end
  if name=='plan' then return true end
  i=i+1
 end
end
local COMPLETE={{spellId=A_ID,quality=A_ID%4,stacks=1,locked=false},{spellId=200011,quality=200011%4,stacks=1,locked=false}}
local DENSE={COMPLETE[1],{spellId='unreadable',quality=0,stacks=1,locked=false}}
local SPARSE={COMPLETE[1]};SPARSE[3]=COMPLETE[2]
for _,shape in ipairs({'number','keyless table'}) do
 for _,case in ipairs({{tag='dense row with an unreadable entry',rows=DENSE},{tag='sparse row',rows=SPARSE}}) do
  local label=shape..', '..case.tag
  boot(nil,{[1]={name='Owned one',verified=true,echoes=plan(200001)},[101]=rowOf(case.rows)})
  local A=Nexus.GameAdapter
  seed(shape,1,101)
  check(A.Slots().bySlot[101].roleSourceValid==false,label..': the projection flags the source as unreadable')
  local survivor
  for _,c in ipairs(A.GetWishlistCandidates()) do if c.slot==101 then survivor=c end end
  check(survivor and survivor.key==A_KEY,label..': the readable survivor alone would carry the key '..tostring(survivor and survivor.key))
  local raw=owner().UpdateStateV1
  local entered=0
  owner().UpdateStateV1=function(mutator,...) if upgradeTransaction(mutator) then entered=entered+1 end return raw(mutator,...) end
  H.Advance(2)
  check(shape=='number' and durable()==101 or (type(durable())=='table' and durable().key==nil),label..': the saved record is left legacy, with no inferred identity')
  check(entered==0,label..': no upgrade transaction was entered: '..entered)
  H.perks.serverBuildSlots[101]=rowOf(COMPLETE);H.Notify()
  H.Advance(6)
  owner().UpdateStateV1=raw
  check(type(durable())=='table' and durable().key==COMPLETE_KEY and durable().name=='Plan A',label..': the complete row is retried and its key persisted: '..tostring(type(durable())=='table' and durable().key))
  unrelatedAuthorizedWrite()
  check(durable().key==COMPLETE_KEY,label..': an authorized write does not undo it')
  local saved=F.Serialize(NexusDB)
  boot(assert(loadstring('return '..saved))(),{[1]={name='Owned one',verified=true,echoes=plan(200001)},[101]=rowOf(COMPLETE)})
  H.Advance(1)
  check(durable().key==COMPLETE_KEY,label..': a later session reads the complete key from the saved table')
 end
end

-- An owner write that is refused is not an attempt: the legacy record stays, and the upgrade is tried again
-- after the retry delay (not on every tick), then persists.
do
 boot(nil,slots('Plan A',A_ID))
 seed('number',1,101)
 local raw=owner().UpdateStateV1
 local attempts,reject=0,true
 owner().UpdateStateV1=function(mutator,...)
  if upgradeTransaction(mutator) then
   attempts=attempts+1
   if reject then return nil end
  end
  return raw(mutator,...)
 end
 H.Advance(2)
 check(durable()==101 and attempts==1,'a refused write leaves the legacy record; one attempt so far: '..attempts)
 H.Advance(2)
 check(attempts==1,'and it is not retried on every tick: '..attempts)
 reject=false
 H.Advance(5)
 check(upgraded('number',durable()) and attempts==2,'after the delay it is retried and persisted: attempts '..attempts)
 H.Advance(3)
 check(attempts==2,'and no further attempt is made once it is done')
 owner().UpdateStateV1=raw
end

-- A store that cannot write durably yet (UpdateStateV1 would take a transient row) is not written to.
do
 boot(nil,slots('Plan A',A_ID))
 seed('number',1,101)
 local raw=owner().UpdateStateV1
 local attempts=0
 owner().UpdateStateV1=function(mutator,...) if upgradeTransaction(mutator) then attempts=attempts+1 end return raw(mutator,...) end
 local rawStatus=Nexus.Store.StateWriteStatus
 Nexus.Store.StateWriteStatus=function() return {mode='loading',reason='lifecycle'} end
 H.Advance(2)
 check(attempts==0 and durable()==101,'while the store cannot write durably no upgrade is attempted: '..attempts)
 Nexus.Store.StateWriteStatus=rawStatus
 H.Advance(5)
 check(attempts==1 and upgraded('number',durable()),'once it can, the upgrade is attempted and persisted')
 owner().UpdateStateV1=raw
end

-- A write that reports success but did not reach the authoritative row is not counted either.
do
 boot(nil,slots('Plan A',A_ID))
 seed('number',1,101)
 local raw=owner().UpdateStateV1
 local attempts=0
 owner().UpdateStateV1=function(mutator,...)
  if upgradeTransaction(mutator) then
   attempts=attempts+1
   if attempts==1 then return true end -- reports success, writes nothing
  end
  return raw(mutator,...)
 end
 H.Advance(2)
 check(attempts==1 and durable()==101,'a write that changed nothing leaves the legacy record')
 H.Advance(6)
 check(attempts==2 and upgraded('number',durable()),'and is retried: attempts '..attempts)
 owner().UpdateStateV1=raw
end

-- Plain-name compatibility: a character whose saved row is still under its plain name (format 5) gets the
-- identity in its canonical row on the first write; the original row is not changed.
do
 local db=F.Database({mutate=function(d) d.chars[F.NAME].loadoutWishlists={[1]=101} end})
 local h=F.Boot(db,function(h)
  h.perks.serverActiveSlot=1
  h.perks.serverBuildSlots=slots('Plan A',A_ID)
 end)
 h.Advance(6)
 local canonical=NexusDB.chars[F.OWNER]
 check(NexusDB.chars[F.NAME].loadoutWishlists[1]==101,'the original plain-name row is untouched')
 check(type(canonical)=='table' and type(canonical.loadoutWishlists)=='table',
  'the canonical character row exists after the first write')
 check(type(canonical.loadoutWishlists[1])=='table' and canonical.loadoutWishlists[1].key==A_KEY,
  'and holds the content identity: '..tostring(canonical.loadoutWishlists[1]))
end

-- An entirely unreadable row yields NO candidate, which is not proof that the slot holds nothing: the check
-- must stay eligible for the bounded retry. The row is corrected to a complete Wishlist later; the first
-- valid echo snapshot is then only a baseline and leaves the mirror generation unchanged, so no unrelated
-- change brings the record back.
for _,shape in ipairs({'number','keyless table'}) do
 local label=shape..', all-unreadable row'
 boot(nil,{[1]={name='Owned one',verified=true,echoes=plan(200001)},
  [101]=rowOf({{spellId='unreadable',quality=0,stacks=1,locked=false}})})
 local A=Nexus.GameAdapter
 seed(shape,1,101)
 check(A.Slots().bySlot[101].roleSourceValid==false,label..': the projection flags the source as unreadable')
 local candidate
 for _,c in ipairs(A.GetWishlistCandidates()) do if c.slot==101 then candidate=c end end
 check(candidate==nil,label..': and produces no candidate')
 local raw=owner().UpdateStateV1
 local entered=0
 owner().UpdateStateV1=function(mutator,...) if upgradeTransaction(mutator) then entered=entered+1 end return raw(mutator,...) end
 H.Advance(2)
 check(shape=='number' and durable()==101 or (type(durable())=='table' and durable().key==nil),label..': the record stays legacy')
 check(entered==0,label..': nothing was written: '..entered)
 local generation=A.PresentationRevisions()
 H.perks.serverBuildSlots[101]=rowOf({COMPLETE[1]});H.Notify()
 H.Advance(1)
 check(A.PresentationRevisions()==generation,label..': the first valid snapshot did not change the slots generation (premise)')
 H.Advance(6)
 owner().UpdateStateV1=raw
 check(upgraded(shape,durable()),label..': the corrected row is retried and its key persisted: '..tostring(type(durable())=='table' and durable().key))
end

-- The slot is ABSENT, and the echo snapshot cannot be taken because ANOTHER row is malformed: absence is not
-- evidence yet, and the first valid snapshot afterwards is only a baseline (the generation stays unchanged), so
-- the record is retried rather than certified.
for _,shape in ipairs({'number','keyless table'}) do
 local label=shape..', absent slot while another row is malformed'
 boot(nil,{[1]={name='Owned one',verified=true,echoes=plan(200001)},
  [102]={name='Other',verified='yes',echoes=plan(200012)}})
 local A=Nexus.GameAdapter
 seed(shape,1,101)
 H.Advance(2)
 check(shape=='number' and durable()==101 or (type(durable())=='table' and durable().key==nil),label..': the record stays legacy')
 local generation=A.PresentationRevisions()
 H.perks.serverBuildSlots[102]={name='Other',verified=false,echoes=plan(200012)}
 H.perks.serverBuildSlots[101]=rowOf({COMPLETE[1]});H.Notify()
 H.Advance(1)
 check(A.PresentationRevisions()==generation,label..': the first valid snapshot did not change the slots generation (premise)')
 H.Advance(6)
 check(upgraded(shape,durable()),label..': the record is retried and upgraded: '..tostring(type(durable())=='table' and durable().key))
end

-- The retry for a row that stays unreadable is bounded: one attempt per delay, not one per tick.
do
 boot(nil,{[1]={name='Owned one',verified=true,echoes=plan(200001)},
  [101]=rowOf({{spellId='unreadable',quality=0,stacks=1,locked=false}})})
 seed('number',1,101)
 local calls=0
 local rawStatus=Nexus.Store.StateWriteStatus
 Nexus.Store.StateWriteStatus=function(...) calls=calls+1;return rawStatus(...) end
 H.Advance(10)
 Nexus.Store.StateWriteStatus=rawStatus
 check(calls>=1 and calls<=4,'an unreadable row is revisited a bounded number of times in 10 s (one per delay, not per tick): '..calls)
 check(durable()==101,'and the record is still legacy')
end

-- A legacy record added after an initially empty assignment map is tried at once.
do
 boot(nil,slots('Plan A',A_ID))
 check(owner().UpdateStateV1(function(s) s.loadoutWishlists={} end),'the assignment map is empty')
 H.Advance(2)
 seed('number',1,101)
 H.Advance(1)
 check(upgraded('number',durable()),'a record added to an empty map is upgraded')
end

print('PASS legacy_assignment_snapshot: '..checks..' checks (legacy number and keyless table: saved table after the poll, an authorized write and a reload; slot reuse; no read writes; mirror not shown; selective upgrade; newer explicit choice; no-legacy poll cost; unassign and restore)')
