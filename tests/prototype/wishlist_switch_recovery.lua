-- Switching between saved Wishlists, and cleaning the list up.
--
-- The reported symptom: "Invalid loadout and saved plan has no distinct current
-- server mirror errors keep happening every time I switch wishlists. My
-- wishlist list is getting clogged."
--
-- The shapes below are SYNTHETIC reconstructions of the two association
-- records a supplied profile was found to hold: the same display name and the
-- same Wishlist mirror hint, but different exact contents and different
-- assignment identities, one of them stored under a map index that is NOT a
-- Saved Build slot. No Echo id, name, character, realm or key from that file
-- is used here, and the file is never executed.
--
-- A Wishlist mirror lives in the build-slot namespace ABOVE the configured
-- Saved Build range: that is what makes an index like 101 a mirror number
-- rather than a loadout. A plan stored under such an index is still the
-- player's plan; what it must never be is an assignment target.
local F=dofile('tests/prototype/format5_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,A

local NAME='Synthetic Switch Plan'
local function Echoes(extra)
 local rows={}
 for index=1,12 do
  rows[#rows+1]={spellId=310000+index,quality=2,stacks=1,locked=false}
 end
 for index=1,3 do
  rows[#rows+1]={spellId=311000+index,quality=3,stacks=1,locked=true}
 end
 if extra then rows[#rows+1]={spellId=319999,quality=2,stacks=1,locked=false} end
 return rows
end

-- A real format-5 profile, so the character row is durable rather than the
-- transient pre-initialization scratch.
local function Boot(mutate)
 H=F.Boot(F.Database({mutate=mutate}))
 A=Nexus.GameAdapter
 check(Nexus.StartupStatus().coreReady==true,'fixture: start-up completed')
 return H
end

-- 1. The three writers of an association agree on what a loadout index is.
-- Before this, one of them accepted any positive integer, which is the only
-- way an association can be stored under a mirror number.
Boot()
local slots=A.Slots()
local maxSlots=tonumber(slots and slots.maxSlots) or 5
check(maxSlots>=1,'fixture: the configured Saved Build range is known: '..maxSlots)
local mirrorIndex=maxSlots+98
check(A.UpdateWishlistAssociationAfterSave(mirrorIndex,maxSlots+2,NAME,Echoes(false),{})==false,
 'a Wishlist mirror number is refused as a loadout index by the save path')
check(A.SetLoadoutWishlistIdentity(mirrorIndex,NAME,Echoes(false),{})==false,
 'and by the identity writer')
check(A.SetLoadoutWishlist(mirrorIndex,maxSlots+2,nil)==false,
 'and by the association writer')
check(NexusDB.chars~=nil,'fixture: the profile exists')
local stored=Nexus.Store.State()
check(stored==nil or type(stored.loadoutWishlists)~='table'
 or stored.loadoutWishlists[mirrorIndex]==nil,
 'and nothing was persisted under that index')
-- The configured range itself is not narrowed: a supported higher slot is
-- still a valid loadout, which is what "do not assume five" means.
check(select(2,A.UpdateWishlistAssociationAfterSave(maxSlots+1,maxSlots+2,NAME,Echoes(false),{}))
 =='invalid loadout','one past the configured range is out of range')

-- 2. A plan already stored under a mirror index is NOT deleted, hidden or
-- rewritten. It stays visible, it says which index it came from, and it says
-- that the index does not name a Saved Build.
local function WithBothPlans(db)
 local row=db.chars[F.NAME]
 row.loadoutWishlists={
  [1]={slot=103,name=NAME,echoes=Echoes(true),assignmentId='assigned:13',designTargets={}},
  [101]={slot=103,name=NAME,echoes=Echoes(false),assignmentId='assigned:6',designTargets={}},
 }
end
Boot(WithBothPlans)
local plans=A.RetainedWishlistPlans()
check(#plans==2,'both retained plans are listed: '..#plans)
local byIndex={}
for _,plan in ipairs(plans) do byIndex[plan.associationIndex]=plan end
check(byIndex[1]~=nil and byIndex[101]~=nil,'including the one under a mirror index')
check(byIndex[1].usable==true,'the in-range association is usable')
check(byIndex[101].usable==false,'the mirror-index association is not a Saved Build target')
check(byIndex[1].key~=byIndex[101].key,
 'the two plans have different exact identities, not just different names')
check(byIndex[1].name==byIndex[101].name,'while sharing the display name, as reported')
check(byIndex[1].ordinaryCopies==byIndex[101].ordinaryCopies+1,
 'and differ by exactly one ordinary copy: '..byIndex[1].ordinaryCopies
 ..' vs '..byIndex[101].ordinaryCopies)
check(byIndex[1].lockedCopies==byIndex[101].lockedCopies,
 'with the same locked design: '..byIndex[1].lockedCopies)

-- 3. Both remain reachable as candidates, and a candidate says where it came
-- from. Neither is silently preferred for having more copies.
local candidates=A.GetWishlistCandidates()
local seenKeys={}
for _,candidate in ipairs(candidates) do
 if candidate.key then seenKeys[candidate.key]=candidate end
end
check(seenKeys[byIndex[1].key]~=nil and seenKeys[byIndex[101].key]~=nil,
 'both plans are offered when switching: '..#candidates..' candidates')
check(seenKeys[byIndex[101].key].associationUsable==false,
 'and the mirror-index one is marked unusable as a target')
check(seenKeys[byIndex[1].key].associationUsable==true,'while the other is not')

-- 4. Forgetting one plan removes exactly that plan, by identity.
local before=#A.RetainedWishlistPlans()
check(A.ForgetWishlistPlan({name=NAME})==false,
 'a name alone never selects a plan to remove')
check(A.ForgetWishlistPlan({})==false,'and neither does an empty selection')
check(#A.RetainedWishlistPlans()==before,'nothing was removed by either attempt')
local ok,why=A.ForgetWishlistPlan({key=byIndex[101].key,assignmentId=byIndex[101].assignmentId})
check(ok==true,'the exact identity removes that plan: '..tostring(why))
local after=A.RetainedWishlistPlans()
check(#after==1,'one plan remains: '..#after)
check(after[1].key==byIndex[1].key,'and it is the OTHER one, untouched')
check(after[1].ordinaryCopies==byIndex[1].ordinaryCopies,
 'with its exact contents preserved: '..after[1].ordinaryCopies)
check(#H.actions==0,'no gameplay, lock, upload or server action was taken')

-- 5. A reload does not resurrect it, and the undo does.
do
 -- The same bytes, read again: a reload, not a fresh profile.
 local carried=F.Serialize(NexusDB)
 H=F.Boot(assert(loadstring('return '..carried))())
 A=Nexus.GameAdapter
 local reloaded=A.RetainedWishlistPlans()
 check(#reloaded==1,'the removed plan does not come back after a reload: '..#reloaded)
 check(reloaded[1].key==byIndex[1].key,'and the kept one is still the kept one')
 check(A.RestoreForgottenWishlistPlan()==true,'the removal can be undone')
 local restored=A.RetainedWishlistPlans()
 check(#restored==2,'both plans are retained again: '..#restored)
 local restoredKeys={}
 for _,plan in ipairs(restored) do restoredKeys[plan.key]=plan end
 check(restoredKeys[byIndex[101].key]~=nil,'including the exact one that was removed')
 check(restoredKeys[byIndex[101].key].associationIndex==101,
  'under the index it had: '..tostring(restoredKeys[byIndex[101].key].associationIndex))
 check(A.RestoreForgottenWishlistPlan()==false,'and the undo is not a second copy')
 check(#A.RetainedWishlistPlans()==2,'so nothing was duplicated: '..#A.RetainedWishlistPlans())
end

-- 5b. The first-run pointer is reconciled in the SAME write. A plan removed
-- while first-run state still names it would otherwise be read back from
-- there on the next load, which is the "it came back" the request forbids.
do
 Boot(function(db)
  local row=db.chars[F.NAME]
  local function Plan()
   return {slot=103,name=NAME,echoes=Echoes(false),
    assignmentId='assigned:6',designTargets={}}
  end
  row.loadoutWishlists={[1]=Plan()}
  row.firstRunWishlist=Plan()
 end)
 local only=A.RetainedWishlistPlans()[1]
 check(only~=nil,'fixture: one retained plan, also named by first-run state')
 local state=Nexus.Store.State()
 check(type(state.firstRunWishlist)=='table','fixture: first-run state names it')
 check(A.ForgetWishlistPlan({key=only.key,assignmentId=only.assignmentId})==true,
  'the plan is forgotten')
 check(Nexus.Store.State().firstRunWishlist==nil,
  'and the first-run pointer to it went with it, in the same write')
 local carried=F.Serialize(NexusDB)
 H=F.Boot(assert(loadstring('return '..carried))())
 A=Nexus.GameAdapter
 check(#A.RetainedWishlistPlans()==0,
  'so a reload does not restore it from first-run state: '..#A.RetainedWishlistPlans())
 check(Nexus.GameAdapter.RestoreForgottenWishlistPlan()==true,'the undo still works')
 check(#A.RetainedWishlistPlans()==1,'and brings the plan back')
 check(type(Nexus.Store.State().firstRunWishlist)=='table',
  'together with the first-run pointer it had')
end

-- 6. Unassign is a different operation: the plan survives it.
Boot(WithBothPlans)
check(A.ClearLoadoutWishlist(1)==true,'unassign clears the association')
local afterUnassign=A.RetainedWishlistPlans()
check(#afterUnassign==1,'the association is gone: '..#afterUnassign)
check(afterUnassign[1].associationIndex==101,'the other record is untouched')

-- 6b. And the Wishlist really is kept. "Unassign Wishlist" says so in its
-- own tooltip, but for a plan with no other copy the record it clears WAS the
-- plan. The removal is retained as the same single undo, so the control can
-- no longer be the last thing that touched a plan the player still wants.
do
 Boot(WithBothPlans)
 local first=A.RetainedWishlistPlans()
 check(#first==2,'fixture: two retained plans')
 check(A.ClearLoadoutWishlist(1)==true,'the Saved Build association is cleared')
 check(#A.RetainedWishlistPlans()==1,'and that record is no longer listed')
 check(A.RestoreForgottenWishlistPlan()==true,
  'the plan the control promised to keep can be recovered')
 local back=A.RetainedWishlistPlans()
 check(#back==2,'both plans are retained again: '..#back)
 local keys={}
 for _,plan in ipairs(back) do keys[plan.key]=plan.associationIndex end
 check(keys[first[1].key]~=nil and keys[first[2].key]~=nil,
  'with their exact identities, under the indexes they had')
 check(#H.actions==0,'and no gameplay or server action was taken')
end

-- 7. The server side. This client exposes no deletion of any kind, so none is
-- offered and the reason is stated rather than a local hide being dressed up
-- as one.
local support=A.ServerWishlistDeletionSupport()
check(type(support)=='table','the client capability is inspected, not assumed')
check(support.supported==false,'no server Wishlist deletion is available on this client')
check(type(support.reason)=='string' and #support.reason>0,
 'and the reason is stated: '..tostring(support.reason))
check(#H.actions==0,'inspecting capability submits nothing')

-- 8. Every candidate is reachable. The menu shows ten rows; with more than
-- ten saved plans the last row pages, so plan eleven can actually be opened.
do
 Boot(function(db)
  local row=db.chars[F.NAME]
  local map={}
  for index=1,14 do
   local rows=Echoes(false)
   -- Each plan differs in one exact copy, so all fourteen are distinct
   -- identities rather than one plan counted fourteen times.
   rows[#rows+1]={spellId=318000+index,quality=2,stacks=1,locked=false}
   map[index<=5 and index or (index+200)]={slot=100+index,name=NAME..' '..index,
    echoes=rows,assignmentId='assigned:'..index,designTargets={}}
  end
  row.loadoutWishlists=map
 end)
 local retained=A.RetainedWishlistPlans()
 check(#retained==14,'fourteen plans are retained: '..#retained)
 local candidates=A.GetWishlistCandidates()
 check(#candidates>=14,'and all of them are candidates: '..#candidates)
 -- The real editor, the real button, the real menu.
 Nexus.WishlistEditor.Show()
 local switch=NexusWishlistEditorSwitchButton
 check(switch~=nil,'the switch control exists on the editor')
 switch:Click()
 local menu=NexusWishlistEditorSwitchMenu
 check(menu~=nil and menu:IsShown(),'the menu opens')
 local function VisibleLabels()
  local out={}
  for _,row in ipairs(menu.rows or {}) do
   if row:IsShown() and row._label then out[#out+1]=row._label:GetText() or '' end
  end
  return out
 end
 local page1=VisibleLabels()
 check(#page1==10,'ten rows are shown: '..#page1)
 local pager=page1[#page1]
 check(pager:find('More wishlists',1,true)~=nil,'the last row pages: '..tostring(pager))
 check(pager:find('of 14',1,true)~=nil,'and states the total: '..tostring(pager))
 -- Page forward until every plan has been listed at least once.
 local seen={}
 for _,label in ipairs(page1) do seen[label]=true end
 local guard=0
 while guard<10 do
  guard=guard+1
  local pagerRow
  for _,row in ipairs(menu.rows or {}) do
   if row:IsShown() and row._label and (row._label:GetText() or ''):find('More wishlists',1,true) then
    pagerRow=row
   end
  end
  if not pagerRow then break end
  pagerRow:Click()
  for _,label in ipairs(VisibleLabels()) do seen[label]=true end
  local labels=VisibleLabels()
  if (labels[#labels] or ''):find('1-9 of 14',1,true) then break end
 end
 local named=0
 for index=1,14 do
  for label in pairs(seen) do
   if label:find(NAME..' '..index,1,true) then named=named+1;break end
  end
 end
 check(named==14,'every one of the fourteen plans can be reached by paging: '..named)
 check(#(menu.rows or {})<=10,
  'and the menu never builds more rows than it shows: '..#(menu.rows or {}))
 check(#H.actions==0,'paging takes no gameplay action')
end

-- 9. The refusal the reporter sees is RETAINED, so a support report of that
-- session shows it. Zero incidents was the thing that made their report
-- say nothing had happened.
do
 Boot(WithBothPlans)
 local support=Nexus.SupportIncidents
 support.Clear()
 check(support.Count()==0,'fixture: nothing retained yet')
 local controller=Nexus.WishlistInternals and Nexus.WishlistInternals.Controller
 check(controller~=nil,'the controller is reachable')
 local instance=controller.New({model=Nexus.WishlistModel.New(),
  store=Nexus.Store,notify=function() end})
 instance.Initialize(A)
 -- A saved plan whose mirror cannot be resolved: exactly the reported state.
 local plan=A.RetainedWishlistPlans()[1]
 check(instance.BeginWishlist({name=NAME,echoes=Echoes(false),
  key=plan.key,assignmentId=plan.assignmentId,designTargets={},
  lockEvidenceVersion=1},1)~=nil,'the editor opens the saved plan')
 local prepared,why=instance.PrepareApply(NAME)
 check(prepared==nil and why=='mirror_unresolved',
  'saving it is refused for the reported reason: '..tostring(why))
 check(support.Count()==1,'and the refusal is retained: '..support.Count())
 local incident=support.Latest()
 check(incident.kind=='wishlist-refusal','under its own kind: '..tostring(incident.kind))
 check(incident.reason=='MIRROR_UNRESOLVED','with the reason: '..tostring(incident.reason))
 check(incident.committed==false,'stating that nothing was written')
 local readiness=incident.readiness or {}
 check(type(readiness.planAlias)=='string' and readiness.planAlias:find('plan-',1,true)==1,
  'the plan is identified by a bounded alias: '..tostring(readiness.planAlias))
 check(readiness.planAlias:find(plan.key,1,true)==nil,'never by its exact key')
 check(tostring(readiness.configuredMaxLoadout)==tostring(maxSlots),
  'the configured range is recorded: '..tostring(readiness.configuredMaxLoadout))
 check(readiness.targetLoadoutSlot==1,'with the target Saved Build slot: '
  ..tostring(readiness.targetLoadoutSlot))
 -- Nothing about the player's data leaks into the report through it.
 local summary=Nexus.SupportReport.Summary()
 check(summary:find('MIRROR_UNRESOLVED',1,true)~=nil,'the report shows the refusal')
 check(summary:find(NAME,1,true)==nil,'without the plan name')
 check(summary:find(plan.key,1,true)==nil,'or its exact identity')
 check(summary:find('319999',1,true)==nil,'or any Echo id')
 check(#H.actions==0,'and no gameplay action followed the refusal')
end

-- 10. The route a player can reach: the editor control, the list of what is
-- retained, a confirmation that states exactly what will and will not be
-- removed, and an undo. Nothing here reaches the Adapter directly.
do
 Boot(WithBothPlans)
 Nexus.WishlistEditor.Show()
 local manage=NexusWishlistEditorManageButton
 check(manage~=nil,'the management control exists on the editor')
 manage:Click()
 local menu=NexusWishlistManageMenu
 check(menu~=nil and menu:IsShown(),'the management list opens')
 local header=menu.header:GetText() or ''
 check(header:find('Saved wishlists on this character: 2',1,true)~=nil,
  'it states how many plans are retained: '..header)
 check(header:find('removals here are local',1,true)~=nil,
  'and that removing here is local only')
 check(header:find('no Wishlist deletion call',1,true)~=nil,
  'stating why a server Wishlist is not removed: '..header)
 local rows,mirrorRow={},nil
 for _,row in ipairs(menu.rows or {}) do
  if row:IsShown() then
   local label=row._label:GetText() or ''
   rows[#rows+1]=label
   if label:find('not a Saved Build (101)',1,true) then mirrorRow=row end
  end
 end
 check(#rows==2,'both retained plans are listed: '..#rows)
 check(mirrorRow~=nil,'the plan stored under a mirror index says so on its row')
 local before=#A.RetainedWishlistPlans()
 mirrorRow:Click()
 check(#A.RetainedWishlistPlans()==before,
  'clicking a row removes nothing on its own: '..#A.RetainedWishlistPlans())
 check(H.popup~=nil and H.popup.which=='NEXUS_FORGET_WISHLIST',
  'it asks first')
 local asked=tostring(H.popup.arg1 or '')
 check(asked:find(NAME,1,true)~=nil,'the confirmation names the plan: '..asked)
 check(asked:find('not a Saved Build',1,true)~=nil,
  'states the association it is removing')
 -- No live server Wishlist resolves for this fixture, so claiming that a
 -- server copy survives would be telling the player the opposite of the
 -- truth about the only copy they have.
 local resolved=false
 for _,plan in ipairs(A.RetainedWishlistPlans()) do
  if plan.associationIndex==101 then resolved=plan.mirrorResolved end
 end
 check(resolved==false,'fixture: no server Wishlist resolves for this plan')
 check(asked:find('this is the only copy',1,true)~=nil,
  'the confirmation says so: '..asked)
 check(asked:find('still matches this plan',1,true)==nil,
  'and does not claim a server copy survives')
 check(asked:find('can undo this',1,true)~=nil,
  'and the undo is named whatever the mirror state is')
 H.AcceptPopup()
 local after=A.RetainedWishlistPlans()
 check(#after==1,'exactly one plan was removed: '..#after)
 check(after[1].associationIndex==1,'and it was the confirmed one')
 check(#H.actions==0,'no gameplay, upload or server action followed')
 -- The undo is offered in the same list, and names what would come back.
 manage:Click()
 local undoRow
 for _,row in ipairs(menu.rows or {}) do
  if row:IsShown() and (row._label:GetText() or ''):find('Undo:',1,true) then
   undoRow=row
  end
 end
 check(undoRow~=nil,'the list offers the undo')
 check((undoRow._label:GetText() or ''):find(NAME,1,true)~=nil,
  'naming the plan that would come back')
 undoRow:Click()
 local restored=A.RetainedWishlistPlans()
 check(#restored==2,'the removal is undone: '..#restored)
 local indexes={}
 for _,plan in ipairs(restored) do indexes[plan.associationIndex]=true end
 check(indexes[101]==true,'under the index it came from')
 check(#H.actions==0,'and the undo takes no gameplay action either')
end

-- 11. A management action that cannot be satisfied is retained with the same
-- bounded facts as a switch refusal, so "I pressed it and nothing happened"
-- is answerable from the support file rather than from memory.
do
 Boot(WithBothPlans)
 local support=Nexus.SupportIncidents
 support.Clear()
 local controller=Nexus.WishlistInternals and Nexus.WishlistInternals.Controller
 local instance=controller.New({model=Nexus.WishlistModel.New(),
  store=Nexus.Store,notify=function() end})
 instance.Initialize(A)
 local plan=A.RetainedWishlistPlans()[1]
 local ok,reason=instance.ForgetRetainedPlan({key=plan.key..'-not-a-plan'})
 check(ok==false,'a plan that is not retained is not removed')
 check(type(reason)=='string' and #reason>0,'and the refusal says why: '..tostring(reason))
 check(#A.RetainedWishlistPlans()==2,'nothing else was removed: '..#A.RetainedWishlistPlans())
 check(support.Count()==1,'the refusal is retained: '..support.Count())
 local incident=support.Latest()
 check(incident.operation=='forget wishlist','naming the operation: '..tostring(incident.operation))
 check(incident.reason=='FORGET_REFUSED','with its own reason: '..tostring(incident.reason))
 check(incident.committed==false,'and stating that nothing was written')
 local readiness=incident.readiness or {}
 check(type(readiness.planAlias)=='string','the plan travels as a bounded alias')
 check(readiness.planAlias:find(plan.key,1,true)==nil,'never as its exact key')
 local summary=Nexus.SupportReport.Summary()
 check(summary:find('FORGET_REFUSED',1,true)~=nil,'the report shows it')
 check(summary:find(NAME,1,true)==nil,'without the plan name')
 check(summary:find(plan.key,1,true)==nil,'or its exact identity')
 check(#H.actions==0,'and no gameplay action followed')
end

-- 12. Taking a removal back when its Saved Build is now used by a different
-- plan. The refusal used to tell the player to unassign that plan, and
-- unassigning overwrote the very record being restored: the wanted plan was
-- lost for good and the other one came back in its place. A restore must
-- never need a destructive step.
do
 Boot(WithBothPlans)
 local plans=A.RetainedWishlistPlans()
 local wanted
 for _,plan in ipairs(plans) do if plan.associationIndex==1 then wanted=plan end end
 check(wanted~=nil,'fixture: a plan is associated with Saved Build 1')
 check(A.ForgetWishlistPlan({associationIndex=1,key=wanted.key,
  assignmentId=wanted.assignmentId})==true,'it is removed')
 -- Saved Build 1 is then used by something else.
 local other={}
 for index=1,12 do other[#other+1]={spellId=310000+index,quality=2,stacks=1,locked=false} end
 other[#other+1]={spellId=317777,quality=2,stacks=1,locked=false}
 check(A.UpdateWishlistAssociationAfterSave(1,104,'Other Plan',other,{})==true,
  'a different plan now holds Saved Build 1')
 local ok,reason,detail=A.RestoreForgottenWishlistPlan()
 check(ok==true,'the removal can still be taken back: '..tostring(reason))
 check(type(detail)=='table' and tonumber(detail.loadoutSlot)~=nil,
  'and it says where it landed: '..tostring(detail and detail.loadoutSlot))
 check(tonumber(detail.loadoutSlot)~=1,'not on the Saved Build that is in use')
 check(tostring(detail.movedFrom)=='1','saying which one it came from')
 local after=A.RetainedWishlistPlans()
 local byIndexAfter={}
 for _,plan in ipairs(after) do byIndexAfter[plan.associationIndex]=plan end
 check(byIndexAfter[1]~=nil and byIndexAfter[1].name=='Other Plan',
  'the plan that holds Saved Build 1 is untouched')
 local recovered=byIndexAfter[tonumber(detail.loadoutSlot)]
 check(recovered~=nil and recovered.key==wanted.key,
  'and the recovered plan is the exact one that was removed')
 check(recovered.ordinaryCopies==wanted.ordinaryCopies
  and recovered.lockedCopies==wanted.lockedCopies,
  'with its exact contents: '..recovered.ordinaryCopies..'/'..recovered.lockedCopies)
 check(#A.ForgottenWishlistPlans()==0,'and it is no longer offered twice')
 check(#H.actions==0,'no gameplay or server action was taken')
end

-- 13. More than one removal stays recoverable, and each is taken back by its
-- own identity. A single slot meant the second removal silently discarded the
-- first, so a player who cleaned up two plans could only ever get one back.
do
 Boot(WithBothPlans)
 local plans=A.RetainedWishlistPlans()
 local firstPlan,secondPlan=plans[1],plans[2]
 check(firstPlan and secondPlan,'fixture: two retained plans')
 check(A.ClearLoadoutWishlist(1)==true,'the first is unassigned')
 check(A.ForgetWishlistPlan({associationIndex=101,key=secondPlan.key,
  assignmentId=secondPlan.assignmentId})==true,'the second is removed')
 local offered=A.ForgottenWishlistPlans()
 check(#offered==2,'both are still recoverable: '..#offered)
 check(offered[1].key==secondPlan.key,'the newest is offered first')
 -- Take back the OLDER one, by its identity, not the newest.
 local ok=A.RestoreForgottenWishlistPlan({key=firstPlan.key,
  assignmentId=firstPlan.assignmentId})
 check(ok==true,'an older removal can be taken back on its own')
 local retained=A.RetainedWishlistPlans()
 check(#retained==1 and retained[1].key==firstPlan.key,
  'and it is the one that was asked for')
 local left=A.ForgottenWishlistPlans()
 check(#left==1 and left[1].key==secondPlan.key,
  'while the other removal is still offered: '..#left)
 check(A.RestoreForgottenWishlistPlan({key=secondPlan.key})==true,
  'and it can be taken back too')
 check(#A.RetainedWishlistPlans()==2,'so nothing was lost by removing both')
 check(#H.actions==0,'no gameplay or server action was taken')
end

-- 14. The switch list says the same thing the management list does about an
-- index that names no Saved Build, so the fact is not only visible to a
-- player who opens the manager.
do
 Boot(WithBothPlans)
 Nexus.WishlistEditor.Show()
 NexusWishlistEditorSwitchButton:Click()
 local labelled=0
 for _,row in ipairs(NexusWishlistEditorSwitchMenu.rows or {}) do
  if row:IsShown() and (row._label:GetText() or ''):find('is not a Saved Build',1,true) then
   labelled=labelled+1
  end
 end
 check(labelled==1,'exactly the out-of-range plan is labelled in the switch list: '..labelled)
end

-- 15. The refusal the report quoted. "Wishlist uploaded and targets saved,
-- but assignment failed (invalid loadout)" and the association refusal behind
-- it were printed and retained nowhere, so the support file of a session full
-- of them held no incidents at all.
do
 Boot(WithBothPlans)
 local support=Nexus.SupportIncidents
 support.Clear()
 local controller=Nexus.WishlistInternals and Nexus.WishlistInternals.Controller
 local instance=controller.New({model=Nexus.WishlistModel.New(),
  store=Nexus.Store,notify=function() end})
 instance.Initialize(A)
 local ok,why=instance.AssociateCandidate({name='Nothing To Associate'})
 check(ok~=true,'associating an unusable candidate is refused: '..tostring(why))
 check(support.Count()==1,'and the refusal is retained: '..support.Count())
 local incident=support.Latest()
 check(incident.operation=='associate wishlist',
  'naming the operation: '..tostring(incident.operation))
 check(incident.reason=='ASSOCIATION_REFUSED',
  'with its own reason: '..tostring(incident.reason))
 check(incident.committed==false,'and stating that nothing was written')
 local summary=Nexus.SupportReport.Summary()
 check(summary:find('ASSOCIATION_REFUSED',1,true)~=nil,'the report shows it')
 check(summary:find('Nothing To Associate',1,true)==nil,'without the name it was given')
 check(#H.actions==0,'and no gameplay action followed')

 -- The same refusal on the path a player with an active Saved Build takes.
 -- Without this the in-range branch had no check behind it at all.
 support.Clear()
 H.perks.serverActiveSlot=1
 H.perks.serverBuildSlots[1]={name='Active Saved Build',verified=true,
  echoes={{spellId=200001,quality=1,stacks=1}}}
 H.Notify();A.Poll();H.Advance(1)
 local slots=A.Slots()
 check(tonumber(slots and slots.activeSlot)==1,
  'fixture: a Saved Build is active: '..tostring(slots and slots.activeSlot))
 local okActive,whyActive=instance.AssociateCandidate({name='Still Nothing To Associate'})
 check(okActive~=true,'associating an unusable candidate is refused there too: '
  ..tostring(whyActive))
 check(support.Count()==1,'and that refusal is retained as well: '..support.Count())
 check(support.Latest().reason=='ASSOCIATION_REFUSED',
  'with the same reason: '..tostring(support.Latest().reason))
 check((support.Latest().readiness or {}).targetLoadoutSlot==1,
  'naming the Saved Build it was refused for: '
  ..tostring((support.Latest().readiness or {}).targetLoadoutSlot))

 -- And when the active slot is a Wishlist mirror number rather than a Saved
 -- Build, which is the state the reported profile was in.
 support.Clear()
 H.perks.serverActiveSlot=102
 H.Notify();A.Poll();H.Advance(1)
 check(tonumber(A.Slots().activeSlot)==102,'fixture: the active slot is a mirror number')
 local okMirror,whyMirror=instance.AssociateCandidate({name='Mirror Active'})
 check(okMirror==false and tostring(whyMirror)=='invalid active loadout',
  'associating against it is refused: '..tostring(whyMirror))
 check(support.Count()==1,'and that refusal is retained too: '..support.Count())
 check((support.Latest().readiness or {}).targetLoadoutSlot==102,
  'naming the slot that is not a Saved Build: '
  ..tostring((support.Latest().readiness or {}).targetLoadoutSlot))
end

-- 16. What the confirmation may say about the server. A mirror NUMBER that
-- is still live is not the same fact as a server Wishlist that holds this
-- plan: the number outlives the contents. Three states, three sentences.
do
 local function WithLiveMirror(rows)
  Boot(function(db)
   db.chars[F.NAME].loadoutWishlists={
    [1]={slot=103,name=NAME,echoes=Echoes(false),assignmentId='assigned:6',designTargets={}},
   }
  end)
  H.perks.serverBuildSlots[103]={name='Mirror',verified=false,echoes=rows}
  H.Notify();A.Poll();H.Advance(1)
  return A.RetainedWishlistPlans()[1]
 end
 -- The server holds exactly these contents.
 local same=WithLiveMirror(Echoes(false))
 check(same~=nil,'fixture: the plan is retained')
 check(same.mirrorResolved==true,'an exact server copy is reported as such')
 check(same.mirrorSlotLive==true,'and its slot is live')
 -- The slot is still there, holding something else.
 local other=Echoes(false)
 other[#other+1]={spellId=316666,quality=2,stacks=1,locked=false}
 local moved=WithLiveMirror(other)
 check(moved.mirrorSlotLive==true,'the slot is still live when its contents changed')
 check(moved.mirrorResolved==false,
  'but no server Wishlist holds this plan, and it is not reported as one')
 -- What the player is asked, in that middle state.
 Nexus.WishlistEditor.Show()
 NexusWishlistEditorManageButton:Click()
 local row
 for _,candidate in ipairs(NexusWishlistManageMenu.rows or {}) do
  if candidate:IsShown() and (candidate._label:GetText() or ''):find(NAME,1,true) then
   row=candidate
  end
 end
 check(row~=nil,'the plan is listed for management')
 row:Click()
 local asked=tostring(H.popup and H.popup.arg1 or '')
 check(asked:find('no longer holds these contents',1,true)~=nil,
  'the confirmation says the slot no longer holds this plan: '..asked)
 check(asked:find('holds exactly this plan',1,true)==nil,
  'and does not claim the server holds it')
 check(asked:find('this is the only copy',1,true)==nil,
  'and does not claim there is nothing on the server either')
 check(asked:find('can undo this',1,true)~=nil,'the undo is named here too')
 check(#H.actions==0,'nothing was submitted to the server')
end

-- 17. Recoverability that was promised is not spent by a control that
-- promises the opposite. Unassign keeps the Wishlist; a confirmed removal was
-- told it could be undone. With one bounded list, five Unassigns must not
-- push the confirmed removal out of it.
do
 Boot(function(db)
  local map={}
  for index=1,5 do
   local rows=Echoes(false)
   rows[#rows+1]={spellId=315000+index,quality=2,stacks=1,locked=false}
   map[index]={slot=110+index,name='Assigned '..index,echoes=rows,
    assignmentId='assigned:a'..index,designTargets={}}
  end
  local removed=Echoes(false)
  removed[#removed+1]={spellId=315999,quality=2,stacks=1,locked=false}
  map[207]={slot=120,name='Confirmed Removal',echoes=removed,
   assignmentId='assigned:r',designTargets={}}
  db.chars[F.NAME].loadoutWishlists=map
 end)
 local target
 for _,plan in ipairs(A.RetainedWishlistPlans()) do
  if plan.associationIndex==207 then target=plan end
 end
 check(target~=nil,'fixture: six retained plans, one of them out of range')
 check(A.ForgetWishlistPlan({associationIndex=207,key=target.key,
  assignmentId=target.assignmentId})==true,'one is removed after a confirmation')
 for index=1,5 do
  check(A.ClearLoadoutWishlist(index)==true,'Saved Build '..index..' is unassigned')
 end
 local offered=A.ForgottenWishlistPlans()
 check(#offered==5,'the recoverable list stays bounded: '..#offered)
 local kept=false
 for _,entry in ipairs(offered) do
  if entry.key==target.key then kept=true end
 end
 check(kept==true,'and the confirmed removal is still one of them')
 check(A.RestoreForgottenWishlistPlan({key=target.key})==true,
  'so the undo it was promised still works')
 local back=false
 for _,plan in ipairs(A.RetainedWishlistPlans()) do
  if plan.key==target.key then back=true end
 end
 check(back==true,'and the plan is retained again')
 check(#H.actions==0,'no gameplay or server action was taken')
end

-- 18. A stored record whose contents already appear in the live list is not
-- offered twice -- but it still carries the association it was stored under,
-- or the switch list cannot say that index names no Saved Build.
do
 local shared=Echoes(false)
 Boot(function(db)
  db.chars[F.NAME].loadoutWishlists={
   [207]={slot=104,name='Shadowed Plan',echoes=shared,designTargets={}},
  }
 end)
 H.perks.serverBuildSlots[104]={name='Shadowed Plan',verified=false,
  echoes=Echoes(false)}
 H.Notify();A.Poll();H.Advance(1)
 local found
 for _,candidate in ipairs(A.GetWishlistCandidates()) do
  if candidate.associationIndex==207 then found=candidate end
 end
 check(found~=nil,'the stored association survives deduplication')
 check(found.associationUsable==false,
  'and is still marked as naming no Saved Build')
 Nexus.WishlistEditor.Show()
 NexusWishlistEditorSwitchButton:Click()
 local labelled=0
 for _,row in ipairs(NexusWishlistEditorSwitchMenu.rows or {}) do
  if row:IsShown() and (row._label:GetText() or ''):find('is not a Saved Build',1,true) then
   labelled=labelled+1
  end
 end
 check(labelled==1,'so the switch list still labels it: '..labelled)
end

-- 19. A profile written by a build that kept only one removal. Its record is
-- adopted into the list rather than shadowed by it, so an upgrade does not
-- quietly drop the one thing that build could still have restored.
do
 Boot(function(db)
  local row=db.chars[F.NAME]
  row.loadoutWishlists={}
  row.forgottenWishlist={loadoutSlot=3,record={slot=121,name='Legacy Removal',
   echoes=Echoes(false),assignmentId='assigned:legacy',designTargets={}}}
 end)
 local offered=A.ForgottenWishlistPlans()
 check(#offered==1,'the older shape is still offered: '..#offered)
 check(offered[1].name=='Legacy Removal','naming the plan it holds: '..tostring(offered[1].name))
 check(offered[1].associationIndex==3,'and the index it came from')
 check(A.RestoreForgottenWishlistPlan()==true,'it can be taken back')
 local back=A.RetainedWishlistPlans()
 check(#back==1 and back[1].associationIndex==3,
  'under that index: '..tostring(back[1] and back[1].associationIndex))
 check(#A.ForgottenWishlistPlans()==0,'and it is not offered twice')
 check(#H.actions==0,'no gameplay or server action was taken')
end

print('PASS wishlist_switch_recovery: an index is a loadout or it is not; both plans survive; one exact plan can be forgotten and restored checks='..checks)
