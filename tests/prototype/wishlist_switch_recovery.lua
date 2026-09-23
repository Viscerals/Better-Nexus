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
 check(header:find('server copies cannot be removed here',1,true)~=nil,
  'and that a server Wishlist cannot be removed from this client')
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
 check(asked:find('server is NOT removed',1,true)~=nil,
  'and states that the Wishlist on the server is not removed')
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

print('PASS wishlist_switch_recovery: an index is a loadout or it is not; both plans survive; one exact plan can be forgotten and restored checks='..checks)
