-- A Wishlist save keeps the plan's explicit roles.
--
-- The editor uploads the plan's ordinary rows and commits its locked targets
-- as the design. The association written after the save stored those
-- uploaded rows WITHOUT their role, so an explicit ordinary row became an
-- untyped one. A plan that explicitly asks for ordinary copies of Echoes the
-- character currently holds locked then changed meaning on a save that
-- changed nothing: before it, the HUD still needed those ordinary copies;
-- after it, current locks counted for them (or, with a same-ID locked
-- target, the progress total grew by the locked targets).
--
-- SYNTHETIC shape (invented ids and counts, no reporter data): 8 wanted
-- ordinary Echoes, 2 unwanted ordinary Echoes, 2 Echoes currently locked.
-- Real TOC boot (harness), real association writer, adapter, HUD model,
-- editor and controller save; the synthetic server applies each upload.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local W,U,L={},{},{}
for i=1,8 do W[#W+1]=200000+i end
for i=9,10 do U[#U+1]=200000+i end
for i=11,12 do L[#L+1]=200000+i end
local function Q(id) return id%4 end

local function Run(label,shape)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 local H=dofile('tests/prototype/harness.lua')
 local active={}
 for _,id in ipairs(W) do active[#active+1]={spellId=id,quality=Q(id),stacks=1,locked=false} end
 for _,id in ipairs(U) do active[#active+1]={spellId=id,quality=Q(id),stacks=1,locked=false} end
 for _,id in ipairs(L) do active[#active+1]={spellId=id,quality=Q(id),stacks=1,locked=true} end
 H.perks.serverBuildSlots={[1]={name='Synthetic Active',verified=true,echoes=active}}
 H.perks.serverActiveSlot=1
 -- The server Wishlist holds the plan's ordinary rows.
 local mirror={}
 for _,id in ipairs(W) do mirror[#mirror+1]={spellId=id,quality=Q(id),stacks=1} end
 if shape.ordinaryLocked then for _,id in ipairs(L) do mirror[#mirror+1]={spellId=id,quality=Q(id),stacks=1} end end
 H.perks.serverBuildSlots[101]={name='Synthetic Plan',verified=false,echoes=mirror}
 local granted={}
 for _,id in ipairs(W) do granted[H.names[id]]={{spellId=id,quality=Q(id)}} end
 for _,id in ipairs(U) do granted[H.names[id]]={{spellId=id,quality=Q(id)}} end
 H.granted=granted
 H.locked={};for _,id in ipairs(L) do H.locked[#H.locked+1]={spellId=id,stacks=1} end
 H.Boot()
 local A,E=Nexus.GameAdapter,Nexus.WishlistEditor
 local function Settle() H.Notify();A.Poll();Nexus.RequestRecompute();for _=1,6 do H.Advance(.5) end end
 Settle()
 -- The association: explicit roles unless the shape is untyped.
 local echoes={}
 local flag=shape.untyped and nil or false
 for _,id in ipairs(W) do echoes[#echoes+1]={spellId=id,quality=Q(id),stacks=1,locked=flag} end
 if shape.ordinaryLocked then for _,id in ipairs(L) do echoes[#echoes+1]={spellId=id,quality=Q(id),stacks=1,locked=flag} end end
 local design
 if shape.design=='locked' then
  design={}
  for _,id in ipairs(L) do design[id]={version=1,copies=1,rows={{spellId=id,quality=Q(id),stacks=1,locked=true,sourceRole='locked'}}} end
 elseif shape.design=='empty' then design={} end
 check(A.SetLoadoutWishlistIdentity(1,'Synthetic Plan',echoes,design)==true,label..': fixture: the plan is assigned')
 Settle()
 local function Progress()
  Nexus.Panel.Refresh();H.Advance(.5)
  local p=(Nexus.Panel._lastModel or {}).progress or {}
  local text=table.concat(p.missing or {},' | ')
  local lockedMissing=0
  for _,id in ipairs(L) do if text:find(H.names[id],1,true) then lockedMissing=lockedMissing+1 end end
  return {owned=p.owned,total=p.total,missing=#(p.missing or {}),lockedMissing=lockedMissing,toLock=#(p.toLock or {})}
 end
 local before=Progress()
 -- The real editor, opened on the assignment, saved without any edit.
 local linked=assert(A.GetLoadoutWishlist(1),label..': the assignment resolves')
 local actions0=#H.actions
 check(E.OpenForWishlist(linked,1),label..': the editor opens the assigned plan')
 check(#H.actions==actions0,label..': opening makes no game action')
 local ctrl
 for i=1,200 do local n,v=debug.getupvalue(E.DebugDraftState,i);if n==nil then break end;if n=='wishlistController' then ctrl=v end end
 check(ctrl~=nil,label..': fixture: the editor controller is reachable')
 local data=ctrl.PrepareApply('Synthetic Plan')
 check(data~=nil,label..': the unchanged plan can be saved')
 ctrl.AcceptApply(data)
 for _=1,10 do H.Advance(.5) end
 local upload
 for i=actions0+1,#H.actions do if H.actions[i][1]=='upload' then upload=H.actions[i] end end
 check(upload~=nil,label..': the save uploads')
 local rows={};for _,e in ipairs(upload[4]) do rows[#rows+1]={spellId=e.spellId,quality=e.quality,stacks=e.stacks} end
 H.perks.serverBuildSlots[upload[2]]={name=upload[3],verified=false,echoes=rows}
 Settle()
 local after=Progress()
 local uploadedLocked=0
 for _,e in ipairs(upload[4]) do for _,id in ipairs(L) do if e.spellId==id then uploadedLocked=uploadedLocked+1 end end end
 return before,after,uploadedLocked,H
end

-- 1. The plan explicitly asks for ordinary copies of the two locked Echoes
-- and has no locked targets. The save uploads those ordinary rows, and the
-- plan still needs them afterwards: the same 2 missing of 10.
do
 local before,after,uploaded=Run('ordinary-of-locked',{ordinaryLocked=true,design='empty'})
 check(before.total==10 and before.lockedMissing==2,
  'fixture: before the save the two ordinary copies are needed: '..tostring(before.total)..' / '..before.lockedMissing)
 check(uploaded==2,'the save uploads them as ordinary rows: '..uploaded)
 check(after.total==before.total and after.missing==before.missing and after.lockedMissing==2,
  'after a save that changed nothing the plan means the same: total '..tostring(after.total)
  ..' missing '..after.missing..' (was '..tostring(before.total)..' / '..before.missing..')')
end

-- 2. The same ids are wanted both as ordinary copies and as locked targets.
-- The locked targets are satisfied by the current locks; the ordinary
-- copies are still needed, before and after the save. The progress total
-- does not absorb the locked targets.
do
 local before,after=Run('same-id-both-roles',{ordinaryLocked=true,design='locked'})
 check(before.total==10 and before.lockedMissing==2 and before.toLock==0,
  'fixture: before the save: '..tostring(before.total)..' total, '..before.lockedMissing..' ordinary of locked ids missing')
 check(after.total==before.total and after.lockedMissing==2 and after.toLock==0,
  'after the save the same-ID roles keep their meaning: total '..tostring(after.total)..' missing '..after.lockedMissing)
end

-- 3. Control: ordinary rows and locked targets on different ids. Unchanged.
do
 local before,after=Run('disjoint',{ordinaryLocked=false,design='locked'})
 check(before.total==8 and before.missing==0,'fixture: disjoint plan complete: '..tostring(before.total))
 check(after.total==8 and after.missing==0,'and unchanged after the save: '..tostring(after.total)..' / '..after.missing)
end

-- 4. Control: an untyped plan (no roles known) keeps its existing reading:
-- current locks count for it before the save, and the editor's untyped
-- draft does not upload the locked ids as ordinary rows.
do
 local before,after,uploaded=Run('untyped',{ordinaryLocked=true,untyped=true})
 check(before.total==8 and before.missing==0,'fixture: untyped plan credits current locks: '..tostring(before.total))
 check(uploaded==0,'the untyped draft does not upload the locked ids: '..uploaded)
 check(after.total==8 and after.missing==0,'and reads the same after the save: '..tostring(after.total))
end

print('PASS role_save_keeps_explicit_ordinary checks='..checks)
