-- Legacy locked design targets: the flat source table is retired only when its targets are kept (controls 026, 027).
-- Two writers move the retired flat table NexusDB.lockDesignTargets under the current Wishlist content key
-- in character.lockDesignTargetsBySlot: AutomationRuntime (LockDesignTargetsFor) and WishlistController
-- (LockDesignTargets). Both used to clear the flat table whether or not the move happened, so a refused or
-- unpersisted move, or a key that already held a different bucket, lost the only copy of the desired targets.
-- Contract (this test): the flat table is cleared only after (a) the Store accepted the move AND the bucket
-- reads back equal AND the Store is durable now (Store.StateWriteStatus), or (b) the key already holds an
-- equal bucket AND the Store is durable now. Otherwise it stays, byte for byte; an existing different bucket
-- is never overwritten or merged; a refused move is retried on the next call and lands; repeated calls change
-- nothing once it has; the overlay invalidation (control 025) fires for a created, verified bucket.
--
-- Attribution (control 027): each writer is driven ALONE in the healthy-store scenarios. The editor scenarios
-- keep Plan A (which carries its own design, so automation returns before it reads the flat table) as the
-- active Wishlist and open the legacy Wishlist in the editor without activating it; the automation scenarios
-- close the editor. A wrapper on the Store owner attributes every store call and every bucket-map write
-- attempt to its caller from the stack; each scenario asserts that its own writer ran and the other attempted
-- no write, and a control shows automation inert with Plan A active. Limits, measured: with NexusDB.chars
-- absent the editor writer makes no store call, and with identity not ready neither writer does, so the
-- transient-row case is automation-only and the identity case is a nothing-happens regression check. No
-- natural runtime path to a transient row is demonstrated; the durable guard is defence in depth, covered
-- by the Store.StateWriteStatus cases. Real boot, real editor and adapter.
local H=dofile('tests/prototype/orbs_support.lua')
local A,W=H.A,Nexus.WishlistEditor
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.perks.serverBuildSlots={
 [1]={name='Owned one',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}}}
for i=2,5 do H.perks.serverBuildSlots[i]={name='Owned '..i,verified=true,echoes={{spellId=410003,quality=0,stacks=1}}} end
H.service.GetServerMaxSlots=function() return 5 end
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
local function Buckets() return Nexus.Store.State().lockDesignTargetsBySlot or {} end
local function activate(slot)
 H.perks.serverActiveSlot=slot;H.Notify();A.Poll();Nexus.RequestRecompute();H.Advance(1.5)
end
local function wishlistRevision() local _,_,_,_,r=A.PresentationRevisions();return r end
-- Plan A (slot 1) carries its own design; it stays the active Wishlist for every editor scenario.
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
W.ImportEBH1String(assert(Nexus.Codec.EncodeEBH1(plan({{200080,1}}),'MAGE','Plan A')),'Plan A')
for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()=='Create Wishlist'then f:Click();break end end
H.AcceptPopup();H.now=H.now+3.1
local DESIGN=Clone(A.GetLoadoutWishlist(1).designTargets)
check(DESIGN[200080]~=nil,'the design of Plan A is stored with its assignment')
local OTHER={[200081]=DESIGN[200080]}
check(not Same(DESIGN,OTHER),'the two designs differ')
local keyOf={}
local function legacy(slot,n)
 local ok,why=A.SetLoadoutWishlistIdentity(slot,'Legacy '..slot,legacyContent(n));assert(ok,why)
 H.Notify();A.Poll();H.Advance(.5)
 keyOf[slot]=A.WishlistKey(legacyContent(n))
end
for slot=2,5 do legacy(slot,slot) end
activate(1)

-- Store owner wrapper. Attribution is taken from the stack: the innermost of the two writers' files. Both
-- owner entries are wrapped: the write entry (UpdateStateV1, where bucket-map writes are attempted and can be
-- refused or ghosted) and the read-only entry (ReadStateV1, which the automation writer uses to read the live
-- bucket before deciding whether a move is needed); a read is a store call, never a write.
local owner=Nexus.MainInternals.StoreAuthorityOwner
local realUpdate,realRead=owner.UpdateStateV1,owner.ReadStateV1
local mode
local calls,writes={automation=0,controller=0,other=0},{automation=0,controller=0,other=0}
local function who()
 local tb=debug.traceback('',3)
 local pa,pc=tb:find('AutomationRuntime',1,true),tb:find('WishlistController',1,true)
 if pa and (not pc or pa<pc) then return 'automation' end
 if pc then return 'controller' end
 return 'other'
end
owner.UpdateStateV1=function(mutator,...)
 local w=who();calls[w]=calls[w]+1
 local probe={};pcall(mutator,probe)
 if probe.lockDesignTargetsBySlot~=nil then
  writes[w]=writes[w]+1
  if mode=='refuse' then return false end
  if mode=='ghost' then return true end
 end
 return realUpdate(mutator,...)
end
if type(realRead)=='function' then
 owner.ReadStateV1=function(...)
  local w=who();calls[w]=calls[w]+1
  return realRead(...)
 end
end
local function counters() return {a=calls.automation,c=calls.controller,wa=writes.automation,wc=writes.controller} end
local announced=0
local realNote=A.NoteLockDesignTargetsMoved
A.NoteLockDesignTargetsMoved=function(...) announced=announced+1;return realNote(...) end
local function setBucket(key,design)
 realUpdate(function(c)
  c.lockDesignTargetsBySlot=c.lockDesignTargetsBySlot or {}
  c.lockDesignTargetsBySlot[key]=design and Clone(design) or nil
 end)
end
local function setFlat(design) NexusDB.lockDesignTargets=design and Clone(design) or nil end
local function untouchedFlat(design,why) check(type(NexusDB.lockDesignTargets)=='table' and Same(NexusDB.lockDesignTargets,design),why) end

-- One drive of one writer, alone.
local SLOT={automation=2,editor=3}
local function drive(writer)
 local slot=SLOT[writer]
 if writer=='automation' then
  if NexusEditorFrame then NexusEditorFrame:Hide() end
  activate(slot);Nexus.RequestRecompute();H.Advance(1.5)
 else
  activate(1) -- Plan A, which carries its own design: automation returns before the flat table
  if NexusEditorFrame then NexusEditorFrame:Hide() end
  pcall(W.OpenForWishlist,A.GetLoadoutWishlist(slot),slot)
  H.Advance(1.5)
 end
end
-- Assertion that only the named writer ran (store calls), and that it attempted bucket writes where asked.
local function onlyWriter(writer,before,wantWrites,label)
 local now=counters()
 local mine=writer=='automation' and (now.a-before.a) or (now.c-before.c)
 local other=writer=='automation' and (now.c-before.c) or (now.a-before.a)
 local mineWrites=writer=='automation' and (now.wa-before.wa) or (now.wc-before.wc)
 local otherWrites=writer=='automation' and (now.wc-before.wc) or (now.wa-before.wa)
 check(mine>=1,label..': the '..writer..' writer ran (store calls '..mine..')')
 -- Automation also reads the Store for other reasons every tick, so the other writer is judged by its writes
 -- (and, for the editor, by its calls); automation's inertness in the editor scenarios is shown by the control below.
 check(otherWrites==0 and (writer=='automation' and other==0 or writer=='editor'),label..': the other writer did not run ('..other..' calls, '..otherWrites..' writes)')
 if wantWrites then check(mineWrites>=1,label..': the '..writer..' writer attempted the move ('..mineWrites..')') end
end
local function reset(writer)
 local key=keyOf[SLOT[writer]]
 mode=nil;setBucket(key,nil);setFlat(nil)
end
local function status(fn) local real=Nexus.Store.StateWriteStatus;Nexus.Store.StateWriteStatus=fn;return function() Nexus.Store.StateWriteStatus=real end end

local function scenario(writer)
 local slot=SLOT[writer];local key=keyOf[slot];local L=writer
 -- ===== refused write: nothing lost, retried, then moved once
 do
  reset(writer);setFlat(DESIGN)
  check(Buckets()[key]==nil,L..' refused: precondition, no bucket')
  mode='refuse';local b=counters();local a0,r0=announced,wishlistRevision()
  drive(writer)
  onlyWriter(writer,b,true,L..' refused')
  untouchedFlat(DESIGN,L..' refused: the flat table is untouched, the desired targets are kept')
  check(Buckets()[key]==nil and announced==a0 and wishlistRevision()==r0,L..' refused: no bucket, no announcement, no revision step')
  drive(writer)
  untouchedFlat(DESIGN,L..' refused twice: still untouched')
  mode=nil
  b=counters();drive(writer);onlyWriter(writer,b,true,L..' retry')
  check(NexusDB.lockDesignTargets==nil and Same(Buckets()[key],DESIGN),L..' retry after the refusal: moved, equal to the legacy value, flat table retired')
  check(announced==a0+1 and wishlistRevision()>r0,L..' retry: announced once, revision stepped')
  local a1,r1=announced,wishlistRevision()
  drive(writer);drive(writer)
  check(announced==a1 and wishlistRevision()==r1 and Same(Buckets()[key],DESIGN) and NexusDB.lockDesignTargets==nil,L..' repeated calls after the move change nothing')
 end
 -- ===== accepted but not kept: not verified, so not retired
 do
  reset(writer);setFlat(DESIGN)
  mode='ghost';local b=counters();local a0,r0=announced,wishlistRevision()
  drive(writer);onlyWriter(writer,b,true,L..' unpersisted')
  untouchedFlat(DESIGN,L..' unpersisted: a write the Store accepted but did not keep leaves the flat table untouched')
  check(Buckets()[key]==nil and announced==a0 and wishlistRevision()==r0,L..' unpersisted: nothing announced')
  mode=nil;drive(writer)
  check(NexusDB.lockDesignTargets==nil and Same(Buckets()[key],DESIGN) and announced==a0+1,L..' unpersisted then retried: moved and verified')
 end
 -- ===== existing identical bucket: nothing to preserve, so retired; nothing moved or announced
 do
  reset(writer);setBucket(key,DESIGN);setFlat(DESIGN)
  local b=counters();local a0,r0=announced,wishlistRevision()
  drive(writer);onlyWriter(writer,b,false,L..' identical bucket')
  check(NexusDB.lockDesignTargets==nil and Same(Buckets()[key],DESIGN),L..' identical bucket: the flat table is retired, the bucket is unchanged')
  check(announced==a0 and wishlistRevision()==r0,L..' identical bucket: nothing announced ('..(announced-a0)..' announcements, revision step '..(wishlistRevision()-r0)..')')
 end
 -- ===== conflicting bucket: never overwritten, never merged, source kept
 do
  reset(writer);setBucket(key,OTHER);setFlat(DESIGN)
  local before=Clone(Buckets()[key]);local b=counters();local a0,r0=announced,wishlistRevision()
  for _=1,3 do drive(writer) end
  onlyWriter(writer,b,false,L..' conflict')
  check(Same(Buckets()[key],before) and not Same(Buckets()[key],DESIGN),L..' conflict: the existing bucket is not overwritten or merged')
  untouchedFlat(DESIGN,L..' conflict: the flat table is kept, byte for byte, over repeated calls')
  check(announced==a0 and wishlistRevision()==r0,L..' conflict: nothing announced')
 end
 -- ===== no flat table: no move attempted, nothing announced
 do
  reset(writer)
  local b=counters();local a0,r0=announced,wishlistRevision()
  mode='refuse';drive(writer);mode=nil
  local now=counters()
  check(now.wa==b.wa and now.wc==b.wc and announced==a0 and wishlistRevision()==r0 and NexusDB.lockDesignTargets==nil,L..' no flat table: nothing attempted, nothing announced')
 end
 -- ===== durable guard: the Store accepts and keeps the move, but is not durable now -> the source stays
 for _,case in ipairs({
  {name='loading',fn=function() return {mode='loading',reason='lifecycle'} end},
  {name='unavailable',fn=function() return {mode='unavailable',reason='container'} end},
  {name='throwing',fn=function() error('status read failed') end},
  {name='missing',fn=false},
 }) do
  reset(writer);setFlat(DESIGN)
  local restore=status(case.fn or nil)
  local b=counters();local a0=announced
  drive(writer);onlyWriter(writer,b,true,L..' not durable ('..case.name..')')
  untouchedFlat(DESIGN,L..' not durable ('..case.name..'): the flat table is kept even though the bucket reads back equal')
  check(Same(Buckets()[key],DESIGN) and announced==a0+1,L..' not durable ('..case.name..'): the bucket exists and was announced once')
  drive(writer)
  untouchedFlat(DESIGN,L..' not durable ('..case.name..'): still kept on the next call')
  check(announced==a0+1,L..' not durable ('..case.name..'): not announced again')
  restore()
  drive(writer)
  check(NexusDB.lockDesignTargets==nil and Same(Buckets()[key],DESIGN) and announced==a0+1,L..' durable again ('..case.name..'): the flat table is retired, the bucket is unchanged, nothing more announced')
 end
 -- ===== a transient row: the container is unusable, so the Store would keep a never-persisted row.
 -- Automation only: with NexusDB.chars absent the editor writer makes no store call at all (measured, control 027),
 -- so an editor variant would be satisfied by automation. The editor guard is covered by the status cases above.
 if writer=='automation' then
  reset(writer);setFlat(DESIGN)
  local chars=NexusDB.chars
  local b=counters()
  NexusDB.chars=nil
  drive(writer)
  local saved=NexusDB.lockDesignTargets
  NexusDB.chars=chars
  check(calls.controller==b.c,L..' transient row: the editor writer did not run')
  check(type(saved)=='table' and Same(saved,DESIGN),L..' transient row (no container): the saved flat table is kept')
  check(Buckets()[key]==nil,L..' transient row: nothing reached the saved row')
  drive(writer)
  onlyWriter(writer,b,true,L..' after the container returned')
  check(NexusDB.lockDesignTargets==nil and Same(Buckets()[key],DESIGN),L..' after the container returned: moved into the saved row and retired')
 end
 -- ===== identity not ready: neither writer reaches the Store (a regression check, not a test of the guard)
 do
  reset(writer);setFlat(DESIGN)
  local realUnit=UnitName
  UnitName=function() return nil end
  local w0=counters()
  drive(writer)
  UnitName=realUnit
  local w1=counters()
  check(w1.wa==w0.wa and w1.wc==w0.wc,L..' identity not ready: no bucket write is attempted by either writer')
  check(type(NexusDB.lockDesignTargets)=='table' and Same(NexusDB.lockDesignTargets,DESIGN) and Buckets()[key]==nil,L..' identity not ready: the flat table is kept, no bucket')
  drive(writer)
  check(NexusDB.lockDesignTargets==nil and Same(Buckets()[key],DESIGN),L..' identity ready: moved and retired')
 end
 reset(writer)
end

-- Control: with Plan A active, automation returns before it reads the flat table, so it is inert for the editor scenarios.
do
 setFlat(DESIGN);mode='count'
 if NexusEditorFrame then NexusEditorFrame:Hide() end
 local b=counters()
 for _=1,3 do activate(1);Nexus.RequestRecompute();H.Advance(1.5) end
 local now=counters()
 check(now.wa==b.wa and now.wc==b.wc,'control: with Plan A active, no bucket-map write is attempted by either writer')
 untouchedFlat(DESIGN,'control: with Plan A active, a recompute leaves the flat table untouched')
 check(next(Buckets()[keyOf[2]] or {})==nil and next(Buckets()[keyOf[3]] or {})==nil,'control: no legacy bucket appeared')
 setFlat(nil);mode=nil
end
local othersBefore={}
for k,v in pairs(Buckets()) do othersBefore[k]=Clone(v) end
scenario('automation')
scenario('editor')
for k,v in pairs(othersBefore) do check(Buckets()[k]~=nil and Same(Buckets()[k],v),'an unrelated bucket is untouched: '..tostring(k)) end
owner.UpdateStateV1=realUpdate
if type(realRead)=='function' then owner.ReadStateV1=realRead end
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
 check(account.lockDesignTargets==nil and Same(backing.lockDesignTargetsBySlot[key],DESIGN) and calls==1,'controller alone: moved, verified, retired, announced once (an injected facade is its own authority)')
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
 backing={lockDesignTargetsBySlot={[key]={}}};account={lockDesignTargets=Clone(DESIGN)}
 c=build(backing,account);c.LoadPendingEchoes(content,false,nil)
 check(Same(account.lockDesignTargets,DESIGN) and next(backing.lockDesignTargetsBySlot[key])==nil,'controller alone: an empty bucket is not overwritten and the flat table is kept')
end
print('PASS lock_design_legacy_preservation: healthy-store scenarios drive each writer alone and attribute it; the flat legacy locked-design table is retired only after its targets are kept and the Store reports durable; refused, unpersisted, conflicting and not-durable cases keep it byte for byte and overwrite nothing (the transient-row case is automation-only); retry moves it once; repeated calls change nothing; checks='..checks)
