-- Independent fail-capable review probe: two exact plans share rolled contents.
-- Only synthetic editor upload/assignment paths are used.
local H=dofile('tests/prototype/orbs_support.lua')
local A,M,W=H.A,H.M,Nexus.WishlistEditor
H.perks.serverBuildSlots={
 [1]={name='Owned one',verified=true,echoes={{spellId=410001,quality=1,stacks=1}}},
 [2]={name='Owned two',verified=true,echoes={{spellId=410003,quality=0,stacks=1}}}}
local function plan(lockedId)
 local e={}
 for i=1,79 do e[#e+1]={spellId=200000+i,quality=i%4,stacks=1,locked=false}end
 e[#e+1]={spellId=lockedId,quality=lockedId%4,stacks=1,locked=true}
 return e
end
-- Both permanent target IDs are in the unchanged boot catalog.
local function save(slot,id,name)
 H.perks.serverActiveSlot=slot;H.Notify();A.Poll()
 local code=assert(Nexus.Codec.EncodeEBH1(plan(id),'MAGE',name))
 W.ImportEBH1String(code,name)
 assert(W.DebugDraftState().pending==79 and W.DebugDraftState().pendingLock==1,'actual imported draft has exact roles')
 local b
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()=='Create Wishlist'then b=f;break end end
 assert(b,'normal Create button exists');b:Click();H.AcceptPopup()
 assert(not W.IsApplyPending(),'synthetic save completes')
 H.now=H.now+3.1
 local a=A.AssignedWishlist();print('SAVED',slot,'wanted',name,'displayed',a.name,'state',a.state)
 assert(a.state=='ready' and type(Nexus.Store.State().loadoutWishlists[slot])=='table','assignment saved for requested loadout')
 return a
end
local a=save(1,200080,'Plan A')
local function has(entries,id)
 for _,e in ipairs(entries or {})do if e.spellId==id and e.locked==true then return true end end
 return false
end
assert(has(a.entries,200080),'first saved permanent target reaches Orb authority')
local b=save(2,200081,'Plan B')
assert(has(b.entries,200081),'second saved permanent target reaches Orb authority')
H.perks.serverActiveSlot=1;H.Notify();A.Poll()
local restored=A.AssignedWishlist()
print('RESTORED',restored.name,'identity',restored.identity,'hasA',has(restored.entries,200080),'hasB',has(restored.entries,200081))
H.granted={['Echo 80']={{spellId=200080,quality=0}}};H.Notify();A.Poll()
local started,reason=M.Start(1)
print('AUTOMATIC_START',tostring(started),tostring(reason),'spends',H.Count('orb-spend'),'source',tostring(H.O.source))
assert(has(restored.entries,200080) and not has(restored.entries,200081),'assigned Plan A must retain its own exact permanent design after saving Plan B')
assert(H.Count('orb-spend')==0,'Plan A only acquired permanent-target copy must never enter automatic sacrifice')
print('PASS two saved plans preserve separate permanent designs and source protection')
