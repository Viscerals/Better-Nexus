-- Wishlist overlay: refresh when the retired flat locked-design table moves (W5 follow-up). Two writers
-- move NexusDB.lockDesignTargets under the current Wishlist content key, once: AutomationRuntime
-- (LockDesignTargetsFor, read whenever the active Wishlist is projected) and WishlistController
-- (LockDesignTargets, on an editor open or a save). Both create lockDesignTargetsBySlot[key] without any
-- Wishlist revision moving, so an overlay that had already read the plan kept hiding the moved
-- planned locked targets until some unrelated revision changed. Required: after a MATERIAL move
-- (a bucket really created from the flat table) the overlay shows the moved targets at its next
-- refresh; a no-op (no flat table), a retire-only (the key already has a bucket) or a refused write
-- announces nothing and moves no revision; the legacy values, the bucket contents and the retirement
-- of the flat table are unchanged; switching Wishlists switches the rows; unchanged ticks do no work;
-- planned targets are never shown as owned. Real boot, real editor, real adapter, real overlay frame
-- (the controller writer is also driven alone with an injected adapter and store).
local H=dofile('tests/prototype/orbs_support.lua')
local A,W,O=H.A,Nexus.WishlistEditor,Nexus.WishlistOverlay
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
H.perks.serverBuildSlots={
 [1]={name='Owned one',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
 [2]={name='Owned two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}},
 [3]={name='Owned three',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}},
 [4]={name='Owned four',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}},
 [5]={name='Owned five',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
local function plan(locks)
 local e={}
 for i=1,79 do e[#e+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
 for _,l in ipairs(locks) do e[#e+1]={spellId=l[1],quality=l[1]%4,stacks=l[2],locked=true}end
 return e
end
-- Distinct rolled content without any locked target: (79-n) single copies and one n-copy Echo, 79 copies in all.
local function legacyContent(n)
 local e={}
 for i=1,79-n do e[#e+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
 e[#e+1]={spellId=200000+79-n+1,quality=2,stacks=n,locked=false}
 return e
end
local function saveWithDesign(slot,name,locks)
 H.perks.serverActiveSlot=slot;H.Notify();A.Poll()
 W.ImportEBH1String(assert(Nexus.Codec.EncodeEBH1(plan(locks),'MAGE',name)),name)
 local create
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()=='Create Wishlist'then create=f;break end end
 assert(create);create:Click();H.AcceptPopup();H.now=H.now+3.1
 check(A.AssignedWishlist().name==name and A.AssignedWishlist().state=='ready','assigned with its own design: '..name)
end
local function activate(slot)
 H.perks.serverActiveSlot=slot;H.Notify();A.Poll();Nexus.RequestRecompute();H.Advance(1.5)
end
local function name(id) return A.Catalog().rows[id].name end
local overlayFrame
local function Lines()
 if not overlayFrame then for _,f in ipairs(H.frames)do if f.GetName and f:GetName()=='NexusOverlay' then overlayFrame=f end end end
 local out={}
 for _,r in ipairs(overlayFrame and overlayFrame.regions or {})do
  if r.shown and r.text and r.text~='' then out[#out+1]=(r.text:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''))end
 end
 return out
end
local function LockedRows() local rows={} for i,t in ipairs(Lines())do if t:find('(locked target)',1,true) then rows[#rows+1]={i=i,t=t} end end return rows end
local function Clone(v) if type(v)~='table' then return v end local o={} for k,x in pairs(v) do o[k]=Clone(x) end return o end
local function Count(t) local n=0 for _ in pairs(t or {}) do n=n+1 end return n end
local function Buckets() return Nexus.Store.State().lockDesignTargetsBySlot or {} end
-- Spy on the announcement of a moved table (absent before the correction).
local announced=0
local realNote=A.NoteLockDesignTargetsMoved
if realNote then A.NoteLockDesignTargetsMoved=function(...) announced=announced+1;return realNote(...) end end
local function wishlistRevision() local _,_,_,_,r=A.PresentationRevisions();return r end

-- World: Plan A (slot 1) holds its own design {200080}; slot 2 holds a LEGACY assignment without a design.
saveWithDesign(1,'Plan A',{{200080,1}})
local designA=Clone(A.GetLoadoutWishlist(1).designTargets)
check(designA[200080]~=nil,'the design of Plan A is stored with its assignment')
local function legacy(slot,name,n)
 local ok,why=A.SetLoadoutWishlistIdentity(slot,name,legacyContent(n));assert(ok,why)
 H.Notify();A.Poll();H.Advance(.5)
 return A.WishlistKey(legacyContent(n))
end
local keyL=legacy(2,'Legacy',2)
local keyM=legacy(3,'Legacy B',3)
local keyC=legacy(4,'Legacy C',4)
local keyD=legacy(5,'Legacy D',5)
activate(2)
O.Show();H.Advance(1.5)
check(A.GetLoadoutWishlist(2).designTargets==nil,'the legacy assignment carries no design of its own')
check(#Lines()==78 and #LockedRows()==0,'before any move the overlay shows 78 ordinary rows and no locked target: '..#Lines())

-- ===== Writer 1: AutomationRuntime moves the flat table at its next read of the active Wishlist.
NexusDB.lockDesignTargets=Clone(designA)
check(Buckets()[keyL]==nil,'precondition: no bucket for the legacy content yet')
local revBefore,announcedBefore=wishlistRevision(),announced
Nexus.RequestRecompute();H.Advance(1.5)
check(NexusDB.lockDesignTargets==nil and type(Buckets()[keyL])=='table','the automation read moved the flat table under the content key and retired it')
check(Buckets()[keyL][200080]~=nil and Count(Buckets()[keyL])==Count(designA),'the moved values are the legacy values, unchanged')
H.Advance(1.5)
local rows=LockedRows()
check(#rows==1 and rows[1].t:find(name(200080)..' (locked target)',1,true) and #Lines()==79,'the overlay shows the moved target without any other revision change: '..#rows..' rows, '..#Lines()..' lines')
check(rows[1].t:sub(1,3)=='[ ]' and rows[1].t:find('(0/1)',1,true),'it is a planned target, not owned: '..rows[1].t)
check(wishlistRevision()>revBefore and (not realNote or announced==announcedBefore+1),'the wishlist revision moved once at the move ('..(wishlistRevision()-revBefore)..' step, '..(announced-announcedBefore)..' announcement)')
-- Unchanged frames reuse the model.
local s1=O.Stats();H.Advance(3);local s2=O.Stats()
check(s2.wishlistReads==s1.wishlistReads and s2.rowUpdates==s1.rowUpdates and s2.projectionBuilds==s1.projectionBuilds,'unchanged ticks after the move read nothing and update no row')
-- A second read finds nothing to move: nothing is announced and the revision stays.
local revAfter,annAfter=wishlistRevision(),announced
Nexus.RequestRecompute();H.Advance(1.5)
check(wishlistRevision()==revAfter and announced==annAfter,'a later read moves and announces nothing')
-- Switching Wishlists switches the rows; the moved target belongs to the legacy content only.
activate(1)
rows=LockedRows()
check(#rows==1 and rows[1].t:find(name(200080)..' (locked target)',1,true),'Plan A (own design) shows its own target')
local bucketCount=Count(Buckets())
activate(2)
rows=LockedRows()
check(#rows==1 and #Lines()==79,'back on the legacy plan its moved target shows again')
check(Count(Buckets())==bucketCount,'switching created no bucket')
-- Owned means owned locked copies: an ordinary copy and the plan itself never count.
H.granted={['Echo 80']={{spellId=200080,quality=0}}};H.Notify();A.Poll();H.Advance(1.5)
check(LockedRows()[1].t:sub(1,3)=='[ ]','an ordinary copy does not own the moved locked target')
H.granted={};H.locked={{spellId=200080,stacks=1}};H.Notify();A.Poll();H.Advance(1.5)
check(LockedRows()[1].t:sub(1,3)=='[X]' and LockedRows()[1].t:find('(1/1)',1,true),'one owned locked copy fulfils it')
H.locked={};H.Notify();A.Poll();H.Advance(1.5)

-- ===== No-op and retire-only: nothing is announced, no revision moves, no extra overlay read.
local readsBefore,revBefore2,annBefore2=O.Stats().wishlistReads,wishlistRevision(),announced
Nexus.RequestRecompute();H.Advance(3)
check(wishlistRevision()==revBefore2 and announced==annBefore2 and O.Stats().wishlistReads==readsBefore,'no flat table: no announcement, no revision step, no overlay read')
-- Retire-only: the content key already has a bucket, so the flat table is retired and not moved.
NexusDB.lockDesignTargets={[200081]=1}
local before=Clone(Buckets()[keyL])
Nexus.RequestRecompute();H.Advance(3)
check(NexusDB.lockDesignTargets==nil and Count(Buckets()[keyL])==Count(before) and Buckets()[keyL][200081]==nil,'a flat table never overwrites an existing bucket, and is still retired')
check(wishlistRevision()==revBefore2 and announced==annBefore2,'retire-only moves no revision and announces nothing')

-- ===== Writer 2: WishlistController moves the flat table when the editor opens the Wishlist.
activate(3)
check(A.GetLoadoutWishlist(3).designTargets==nil and #Lines()==77 and #LockedRows()==0,'Legacy B: a second legacy assignment, overlay shows its 77 ordinary rows ('..#Lines()..')')
NexusDB.lockDesignTargets=Clone(designA)
check(Buckets()[keyM]==nil,'precondition: no bucket for Legacy B content')
local rev3,ann3=wishlistRevision(),announced
check(W.OpenForWishlist(A.GetLoadoutWishlist(3),3),'the editor opens Legacy B')
check(NexusDB.lockDesignTargets==nil and type(Buckets()[keyM])=='table' and Buckets()[keyM][200080]~=nil,'the editor open moved the flat table under Legacy B content and retired it')
check(wishlistRevision()>rev3 and (not realNote or announced==ann3+1),'the editor move announced once and the revision stepped')
H.Advance(1.5)
rows=LockedRows()
check(#rows==1 and rows[1].t:find(name(200080)..' (locked target)',1,true) and rows[1].t:sub(1,3)=='[ ]','the overlay shows the target the editor move created, as planned and not owned: '..#rows)

-- ===== Refusal: the Store does not accept the move. Nothing is announced and no revision moves
-- (the flat table is retired by both writers whatever the outcome, as before).
local owner=Nexus.MainInternals.StoreAuthorityOwner
local realUpdate=owner.UpdateStateV1
local refusing=false
local refused=0
owner.UpdateStateV1=function(mutator,...)
 if refusing then
  local probe={};pcall(mutator,probe)
  if probe.lockDesignTargetsBySlot~=nil then refused=refused+1;return false end
 end
 return realUpdate(mutator,...)
end
activate(4)
NexusDB.lockDesignTargets=Clone(designA)
local revR,annR,readsR=wishlistRevision(),announced,O.Stats().wishlistReads
local refusedAuto=refused
refusing=true;Nexus.RequestRecompute();H.Advance(2);refusing=false
refusedAuto=refused-refusedAuto
check(refusedAuto>=1,'the refusal reached the automation writer ('..refused..')')
check(Buckets()[keyC]==nil and #LockedRows()==0,'refused (automation writer): no bucket, no locked row')
check(wishlistRevision()==revR and announced==annR,'refused (automation writer): no announcement and no revision step')
activate(5)
if NexusEditorFrame then NexusEditorFrame:Hide() end
NexusDB.lockDesignTargets=Clone(designA)
revR,annR=wishlistRevision(),announced
local refusedBefore=refused
refusing=true;pcall(W.OpenForWishlist,A.GetLoadoutWishlist(5),5);refusing=false
check(refused>refusedBefore,'the refusal reached the controller writer ('..refused..')')
check(Buckets()[keyD]==nil and wishlistRevision()==revR and announced==annR,'refused (controller writer): no bucket, no announcement, no revision step')
owner.UpdateStateV1=realUpdate

-- (last: it re-initialises the adapter with an injected store)
-- ===== The controller writer alone (injected adapter and store): moved, retire-only, none.
do
 local calls=0
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
 local content=legacyContent(2)
 local key=A.WishlistKey(content)
 local backing,account={},{lockDesignTargets={[200020]=true}}
 local c=build(backing,account)
 c.LoadPendingEchoes(content,false,nil)
 check(backing.lockDesignTargetsBySlot and backing.lockDesignTargetsBySlot[key] and backing.lockDesignTargetsBySlot[key][200020]==true and account.lockDesignTargets==nil,'controller alone: the flat table moved with its value and was retired')
 check(calls==1,'controller alone: one announcement for the move: '..calls)
 c.LoadPendingEchoes(content,false,nil)
 check(calls==1,'controller alone: a second open announces nothing')
 calls=0
 backing={lockDesignTargetsBySlot={[key]={[200030]=true}}};account={lockDesignTargets={[200021]=true}}
 c=build(backing,account);c.LoadPendingEchoes(content,false,nil)
 check(backing.lockDesignTargetsBySlot[key][200030]==true and backing.lockDesignTargetsBySlot[key][200021]==nil and account.lockDesignTargets==nil and calls==0,'controller alone: an existing bucket wins, the flat table is retired, nothing is announced')
 calls=0
 backing={};account={}
 c=build(backing,account);c.LoadPendingEchoes(content,false,nil)
 check(calls==0 and backing.lockDesignTargetsBySlot==nil,'controller alone: no flat table, no bucket, nothing announced')
end

check(H.Count('orb-spend')==0,'no Orb spend')
for _,a in ipairs(H.actions)do check(a[1]~='unlock' and a[1]~='lock','no lock or unlock action: '..tostring(a[1])) end
print('PASS wishlist_overlay_legacy_design_refresh: both writers of the retired flat locked-design table announce a material move; the overlay shows the moved planned targets at its next refresh without another revision; no-op, retire-only and refused writes announce nothing; values, retirement and ownership unchanged; switching and unchanged ticks checked checks='..checks)
