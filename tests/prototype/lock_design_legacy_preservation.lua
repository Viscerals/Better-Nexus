-- Legacy locked design targets: the flat source table is retired only when its targets are kept (control 026).
-- Two writers move the retired flat table NexusDB.lockDesignTargets under the current Wishlist content key
-- in character.lockDesignTargetsBySlot: AutomationRuntime (LockDesignTargetsFor) and WishlistController
-- (LockDesignTargets). Both cleared the flat table whether or not the move happened, so a refused or
-- unpersisted move, or a key that already held a different bucket, lost the only copy of the desired targets.
-- Contract (this test): the flat table is cleared only after (a) the Store accepted the move AND the bucket
-- reads back equal to it, or (b) the key already holds an equal bucket. Otherwise it stays, byte for byte;
-- an existing different bucket is never overwritten or merged; a refused move is retried on the next call
-- and lands; repeated calls change nothing once it has; nothing is announced unless a bucket was created
-- and verified (the overlay invalidation of control 025). Real boot, real editor and adapter; a wrapper on
-- the Store owner simulates a refused write and a write that is accepted but not kept.
local H=dofile('tests/prototype/orbs_support.lua')
local A,W=H.A,Nexus.WishlistEditor
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.perks.serverBuildSlots={
 [1]={name='Owned one',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}}}
for i=2,9 do H.perks.serverBuildSlots[i]={name='Owned '..i,verified=true,echoes={{spellId=410003,quality=0,stacks=1}}} end
H.service.GetServerMaxSlots=function() return 9 end
local function plan(locks)
 local e={}
 for i=1,79 do e[#e+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
 for _,l in ipairs(locks) do e[#e+1]={spellId=l[1],quality=l[1]%4,stacks=l[2],locked=true}end
 return e
end
local function legacyContent(n)
 local e={}
 for i=1,79-n do e[#e+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
 e[#e+1]={spellId=200000+79-n+1,quality=2,stacks=n,locked=false}
 return e
end
local function Clone(v) if type(v)~='table' then return v end local o={} for k,x in pairs(v) do o[k]=Clone(x) end return o end
local function Same(a,b) if type(a)~='table' or type(b)~='table' then return a==b end
 for k,v in pairs(a) do if not Same(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end return true end
local function Count(t) local n=0 for _ in pairs(t or {}) do n=n+1 end return n end
local function Buckets() return Nexus.Store.State().lockDesignTargetsBySlot or {} end
local function activate(slot)
 H.perks.serverActiveSlot=slot;H.Notify();A.Poll();Nexus.RequestRecompute();H.Advance(1.5)
end
local function wishlistRevision() local _,_,_,_,r=A.PresentationRevisions();return r end
-- A design to keep (a real committed design of Plan A) and a different one.
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
W.ImportEBH1String(assert(Nexus.Codec.EncodeEBH1(plan({{200080,1}}),'MAGE','Plan A')),'Plan A')
for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()=='Create Wishlist'then f:Click();break end end
H.AcceptPopup();H.now=H.now+3.1
local DESIGN=Clone(A.GetLoadoutWishlist(1).designTargets)
check(DESIGN[200080]~=nil,'the design of Plan A is stored with its assignment')
local OTHER={[200081]=DESIGN[200080]} -- a different design (another Echo, same value shape)
check(not Same(DESIGN,OTHER),'the two designs differ')

-- Legacy plans: one slot per scenario; assignments carry no design of their own.
local slotOf,keyOf={},{}
local function legacy(slot,n)
 local ok,why=A.SetLoadoutWishlistIdentity(slot,'Legacy '..slot,legacyContent(n));assert(ok,why)
 H.Notify();A.Poll();H.Advance(.5)
 slotOf[n]=slot;keyOf[slot]=A.WishlistKey(legacyContent(n))
 return keyOf[slot]
end
for slot=2,9 do legacy(slot,slot) end
activate(2)

-- Store owner wrapper: modes 'refuse' (a write that creates the bucket map is refused), 'ghost' (such a write
-- is accepted but kept nowhere) and 'count' (passed through). `writes` counts attempted bucket-map writes.
local owner=Nexus.MainInternals.StoreAuthorityOwner
local realUpdate=owner.UpdateStateV1
local mode,writes=nil,0
owner.UpdateStateV1=function(mutator,...)
 if mode then
  local probe={};pcall(mutator,probe)
  if probe.lockDesignTargetsBySlot~=nil then
   writes=writes+1
   if mode=='refuse' then return false end
   if mode=='ghost' then return true end
  end
 end
 return realUpdate(mutator,...)
end
local announced=0
local realNote=A.NoteLockDesignTargetsMoved
A.NoteLockDesignTargetsMoved=function(...) announced=announced+1;return realNote(...) end
local function seedBucket(key,design)
 realUpdate(function(c) c.lockDesignTargetsBySlot=c.lockDesignTargetsBySlot or {};c.lockDesignTargetsBySlot[key]=Clone(design) end)
end
local function others(exceptKey)
 local t={};for k,v in pairs(Buckets()) do if k~=exceptKey then t[k]=Clone(v) end end return t
end
local function setFlat(design) NexusDB.lockDesignTargets=Clone(design) end
local function untouchedFlat(design,why) check(type(NexusDB.lockDesignTargets)=='table' and Same(NexusDB.lockDesignTargets,design),why) end

-- Drives writer 1 (automation) or writer 2 (the editor) once for the Wishlist in `slot`.
local function drive(writer,slot)
 if writer=='automation' then
  activate(slot);Nexus.RequestRecompute();H.Advance(1.5)
 else
  activate(slot)
  if NexusEditorFrame then NexusEditorFrame:Hide() end
  W.OpenForWishlist(A.GetLoadoutWishlist(slot),slot)
 end
end
local slotFor={automation={refuse=2,ghost=3,identical=4,conflict=5,noop=6},editor={refuse=7,ghost=8,identical=9}}

local function scenario(writer)
 local s=slotFor[writer]
 -- ===== refused write: nothing lost, retried, then moved once
 do
  local slot=s.refuse;local key=keyOf[slot]
  activate(slot)
  setFlat(DESIGN)
  check(Buckets()[key]==nil,writer..' refused: precondition, no bucket')
  mode='refuse';writes=0;local a0,r0=announced,wishlistRevision()
  drive(writer,slot)
  check(writes>=1,writer..' refused: the move was attempted and refused ('..writes..')')
  untouchedFlat(DESIGN,writer..' refused: the flat table is untouched, the desired targets are kept')
  check(Buckets()[key]==nil and announced==a0 and wishlistRevision()==r0,writer..' refused: no bucket, no announcement, no revision step')
  drive(writer,slot)
  untouchedFlat(DESIGN,writer..' refused twice: still untouched')
  mode=nil
  drive(writer,slot)
  check(NexusDB.lockDesignTargets==nil and type(Buckets()[key])=='table' and Same(Buckets()[key],DESIGN),writer..' retry after the refusal: moved, equal to the legacy value, flat table retired')
  check(announced==a0+1 and wishlistRevision()>r0,writer..' retry: announced once, revision stepped')
  local a1,r1,w1=announced,wishlistRevision(),writes
  drive(writer,slot);drive(writer,slot)
  check(announced==a1 and wishlistRevision()==r1 and Same(Buckets()[key],DESIGN) and NexusDB.lockDesignTargets==nil,writer..' repeated calls after the move change nothing')
 end
 -- ===== accepted but not kept: not verified, so not retired
 do
  local slot=s.ghost;local key=keyOf[slot]
  activate(slot);setFlat(DESIGN)
  mode='ghost';writes=0;local a0,r0=announced,wishlistRevision()
  drive(writer,slot)
  check(writes>=1,writer..' unpersisted: the move was attempted')
  untouchedFlat(DESIGN,writer..' unpersisted: a write the Store accepted but did not keep leaves the flat table untouched')
  check(Buckets()[key]==nil and announced==a0 and wishlistRevision()==r0,writer..' unpersisted: nothing announced')
  mode=nil
  drive(writer,slot)
  check(NexusDB.lockDesignTargets==nil and Same(Buckets()[key],DESIGN) and announced==a0+1,writer..' unpersisted then retried: moved and verified')
 end
 -- ===== existing identical bucket: nothing to preserve, so retired; nothing moved or announced
 do
  local slot=s.identical;local key=keyOf[slot]
  activate(slot);seedBucket(key,DESIGN);setFlat(DESIGN)
  local a0,r0=announced,wishlistRevision()
  drive(writer,slot)
  check(NexusDB.lockDesignTargets==nil and Same(Buckets()[key],DESIGN),writer..' identical bucket: the flat table is retired, the bucket is unchanged')
  check(announced==a0 and wishlistRevision()==r0,writer..' identical bucket: nothing announced')
 end
 -- ===== conflicting bucket: never overwritten, never merged, source kept (automation writer; editor below)
 if s.conflict then
  local slot=s.conflict;local key=keyOf[slot]
  activate(slot);seedBucket(key,OTHER);setFlat(DESIGN)
  local before=Clone(Buckets()[key]);local a0,r0,wr0=announced,wishlistRevision(),writes
  mode='count'
  for _=1,4 do drive(writer,slot) end
  mode=nil
  check(Same(Buckets()[key],before) and not Same(Buckets()[key],DESIGN),writer..' conflict: the existing bucket is not overwritten or merged')
  untouchedFlat(DESIGN,writer..' conflict: the flat table is kept, byte for byte, over repeated calls')
  check(writer=='editor' or writes==wr0,writer..' conflict: no write was attempted ('..(writes-wr0)..')')
  check(announced==a0 and wishlistRevision()==r0,writer..' conflict: nothing announced')
  NexusDB.lockDesignTargets=nil
 end
 -- ===== no flat table: no work, no announcement
 if s.noop then
  local slot=s.noop
  activate(slot);NexusDB.lockDesignTargets=nil
  local a0,r0=announced,wishlistRevision();writes=0
  mode='refuse';drive(writer,slot);mode=nil
  check(writes==0 and announced==a0 and wishlistRevision()==r0 and NexusDB.lockDesignTargets==nil,writer..' no flat table: nothing attempted, nothing announced')
 end
end

local othersBefore=others(nil)
scenario('automation')
scenario('editor')
-- editor conflict on a content that has no bucket yet: seed a different bucket first
do
 local slot=slotFor.automation.noop;local key=keyOf[slot]
 activate(slot);seedBucket(key,OTHER);setFlat(DESIGN)
 local before=Clone(Buckets()[key]);local a0,r0=announced,wishlistRevision();local wr0=writes
 for _=1,3 do drive('editor',slot) end
 check(Same(Buckets()[key],before) and not Same(Buckets()[key],DESIGN),'editor conflict: the existing bucket is not overwritten or merged')
 untouchedFlat(DESIGN,'editor conflict: the flat table is kept, byte for byte, over repeated opens')
 check(announced==a0 and wishlistRevision()==r0,'editor conflict: nothing announced, no revision step')
 NexusDB.lockDesignTargets=nil
 -- no flat table: an editor open attempts no write and announces nothing
 local wr1=writes;drive('editor',slot);mode='refuse';drive('editor',slot);mode=nil
 check(writes==wr1 and announced==a0,'editor no flat table: nothing attempted, nothing announced')
end
-- Other buckets are untouched by every scenario above.
for k,v in pairs(othersBefore) do check(Buckets()[k]~=nil and Same(Buckets()[k],v),'an unrelated bucket is untouched: '..tostring(k)) end
owner.UpdateStateV1=realUpdate
A.NoteLockDesignTargetsMoved=realNote

-- ===== The controller writer alone (injected adapter and store), last: it re-initialises the adapter.
do
 local calls=0
 local content=legacyContent(2);local key=A.WishlistKey(content)
 local function build(backing,account)
  local settings={}
  local store={State=function() return backing end,Settings=function() return settings end}
  local adapter={};for k,v in pairs(A) do adapter[k]=v end
  adapter.NoteLockDesignTargetsMoved=function() calls=calls+1 end
  A.Init({},store)
  local c=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=store,accountRoot=function()return account end,notify=function()end})
  c.Initialize(adapter)
  return c
 end
 local backing,account={},{lockDesignTargets=Clone(DESIGN)}
 local c=build(backing,account);c.LoadPendingEchoes(content,false,nil)
 check(account.lockDesignTargets==nil and Same(backing.lockDesignTargetsBySlot[key],DESIGN) and calls==1,'controller alone: moved, verified, retired, announced once')
 c.LoadPendingEchoes(content,false,nil)
 check(calls==1,'controller alone: a second open announces nothing')
 calls=0
 backing={lockDesignTargetsBySlot={[key]=Clone(DESIGN)}};account={lockDesignTargets=Clone(DESIGN)}
 c=build(backing,account);c.LoadPendingEchoes(content,false,nil)
 check(account.lockDesignTargets==nil and Same(backing.lockDesignTargetsBySlot[key],DESIGN) and calls==0,'controller alone: an identical bucket retires the flat table, announces nothing')
 backing={lockDesignTargetsBySlot={[key]=Clone(OTHER)}};account={lockDesignTargets=Clone(DESIGN)}
 c=build(backing,account)
 for _=1,3 do c.LoadPendingEchoes(content,false,nil) end
 check(Same(account.lockDesignTargets,DESIGN) and Same(backing.lockDesignTargetsBySlot[key],OTHER) and calls==0,'controller alone: a different bucket is not overwritten and the flat table is kept over repeated opens')
 backing={};account={}
 c=build(backing,account);c.LoadPendingEchoes(content,false,nil)
 check(calls==0 and backing.lockDesignTargetsBySlot==nil,'controller alone: no flat table, nothing moved')
 -- an empty existing bucket is a different bucket: not overwritten, flat table kept
 backing={lockDesignTargetsBySlot={[key]={}}};account={lockDesignTargets=Clone(DESIGN)}
 c=build(backing,account);c.LoadPendingEchoes(content,false,nil)
 check(Same(account.lockDesignTargets,DESIGN) and next(backing.lockDesignTargetsBySlot[key])==nil,'controller alone: an empty bucket is not overwritten and the flat table is kept')
end
print('PASS lock_design_legacy_preservation: the flat legacy locked-design table is retired only after its targets are kept (accepted and verified move, or an identical bucket); refused, unpersisted and conflicting cases keep it byte for byte and overwrite nothing; retry moves it once; repeated calls change nothing; both writers checks='..checks)
