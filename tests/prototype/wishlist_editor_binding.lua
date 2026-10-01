-- Wishlist editor binding across saves (BN-CONTROL-FULL-REVIEW-20261001-
-- 005-CORRECTION-01). A save stamps a new assignment identity; the open
-- editor kept the old one, so the second save of an existing first-run plan
-- in one session was no longer proven to be that plan's and its assignment
-- update was lost. Required: the editor's proven binding follows its own
-- successful save (the identity checks are unchanged); an explicit Unassign
-- or reassignment made while the editor is open stays authoritative, for the
-- first-run plan and for numbered Saved Builds alike. Each row checks the
-- uploaded contents and the stored first-run/slot assignment contents.
-- Synthetic server and mirrors only; real editor buttons, controller and
-- adapter.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,A
local E1={{spellId=201172,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local function Boot(o)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonholdEchoJournal=nil
 H=dofile('tests/prototype/harness.lua')
 local create=CreateFrame
 CreateFrame=function(kind,name,parent,template)
  local f=create(kind,name,parent,template)
  if template=='UIPanelCloseButton' then f._testTemplateClose=true;f:SetScript('OnClick',function(self)self:GetParent():Hide()end) end
  return f
 end
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201173,'Echo Six',0,5);H.AddEcho(201174,'Echo Free',0,5)
 H.AddEcho(200767,'Echo Lock',0,5)
 if o.maxSlots==false then H.service.GetServerMaxSlots=function() return nil end
 else H.service.GetServerMaxSlots=function() return o.maxSlots or 5 end end
 H.perks.serverBuildSlots=o.slots
 H.perks.serverActiveSlot=o.active or 0
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function()error('editing must not spend')end}
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
end
local function Slots6()
 return {[1]={name='One',verified=true,echoes=H and H.Clone(E1) or E1},[6]={name='Six',verified=true,echoes=E6},
  [101]={name='W-One',verified=false,echoes=E1},[106]={name='W-Six',verified=false,echoes=E6},
  [107]={name='W-Free',verified=false,echoes=EF}}
end
local function button(text)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end end
 error('visible button absent: '..text)
end
local function selected(id)
 for _,f in ipairs(H.frames)do if f:IsVisible() and f.plus and f.data and f.data.spellId==id then return f end end
 error('visible selected row absent: '..id)
end
local function menuRow(label)
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f:IsVisible() and f._label and tostring(f._label:GetText() or ''):find(label,1,true) then return f end
 end
 error('visible switch-menu row absent: '..label)
end
local function closeEditor()
 for _,f in ipairs(NexusEditorFrame.children)do if f._testTemplateClose then f:Click();return end end
 error('editor Close control absent')
end
-- The editor's own controller (no public handle): its editing context.
local function Ctx()
 local show=Nexus.WishlistEditor.Show
 for i=1,255 do local n,v=debug.getupvalue(show,i);if not n then break end
  if n=='wishlistController' then return v.EditingContext() or {} end end
 error('editor controller not found')
end
local function Assignment(slot)
 local s=Nexus.Store.State();local r=s.loadoutWishlists and s.loadoutWishlists[slot]
 return r and {name=r.name,key=r.key,id=r.assignmentId} or nil
end
local function Same(a,b) return (a==nil and b==nil) or (a and b and a.name==b.name and a.key==b.key and a.id==b.id) end
local function FirstRun() local f=Nexus.Store.State().firstRunWishlist;return f and {name=f.name,key=f.key,id=f.assignmentId} or nil end
local function Assign(slot,name,echoes) local ok,why=A.SetLoadoutWishlistIdentity(slot,name,H.Clone(echoes));assert(ok,why) end
local function Uploads() local n,last=0,nil;for _,a in ipairs(H.actions)do if a[1]=='upload' then n=n+1;last=a end end;return n,last end
-- The server's mirror of an upload. A Create uploads to the designed-slot
-- sentinel 0; the server lists the new Wishlist in a designed slot above the
-- declared Saved Builds (108 here).
local function Mirror(slot,name,entries)
 if slot==0 then slot=108 end
 local rows=H.Clone(H.perks.serverBuildSlots or {});rows[slot]={name=name,verified=false,echoes=H.Clone(entries)}
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll();H.Advance(4)
end
local function CreatePlan(name,id)
 NexusWishlistNameInput:SetText(name)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==id then f:Click();break end end
 button('Create Wishlist'):Click()
 check(H.popup and H.popup.which=='WISHLISTREALIZER_CREATE_WISHLIST','Create asks for confirmation ('..name..')')
 H.AcceptPopup()
 local n,l=Uploads();return n,l
end
-- Edit the open Wishlist (one more copy of `id`), press Save and accept.
local function SaveEdit(id)
 selected(id).plus:Click()
 button('Save Wishlist'):Click()
 check(H.popup and H.popup.which=='WISHLISTREALIZER_UPDATE_WISHLIST','Save asks for confirmation')
 H.AcceptPopup()
 local n,last=Uploads();return n,last
end

local function Stored(where)
 local s=Nexus.Store.State()
 if where=='first' then return s.firstRunWishlist end
 return s.loadoutWishlists and s.loadoutWishlists[where]
end
local function Copies(rec,id)
 if type(rec)~='table' then return nil end
 local n=0;for _,e in ipairs(rec.echoes or {})do if e.spellId==id then n=n+(e.stacks or 1) end end;return n
end
local function Sent(last,id) return Copies({echoes=last[4]},id) end
-- The server lists a Create's new Wishlist in a free designed slot.
local function MirrorAt(slot,last) Mirror(slot,last[3],last[4]) end
local function Bound(where) return Ctx().assignmentId~=nil and Ctx().assignmentId==Stored(where).assignmentId end
local function Saved(id,copies,label)
 local n,last=SaveEdit(id);Mirror(last[2],last[3],last[4])
 check(Sent(last,id)==copies,label..': the upload holds '..copies..' copies')
 return last
end
-- An existing first-run plan, open in the editor (no active Saved Build).
local function FirstRunWorld(slots)
 Boot({maxSlots=6,active=0,slots=slots or {[107]={name='W-Free',verified=false,echoes=EF}}})
 SlashCmdList.NEXUS('editor')
 local c,l=CreatePlan('First plan',201172);MirrorAt(108,l);closeEditor()
 SlashCmdList.NEXUS('editor')
 check(Ctx().name=='First plan' and Bound('first'),'fixture: the first-run plan is open and bound')
end
-- Six declared Saved Builds; slot 6 active; slots 1 and 6 assigned.
local function LoadoutWorld()
 Boot({maxSlots=6,active=6,slots=Slots6()})
 Assign(1,'W-One',E1);Assign(6,'W-Six',E6);H.Notify();A.Poll();H.Advance(1)
 SlashCmdList.NEXUS('editor')
 check(Ctx().loadoutSlot==6 and Ctx().name=='W-Six' and Bound(6),'fixture: Saved Build 6 and W-Six are open and bound')
 return Assignment(1)
end
local function FirstRunIs(copies,label)
 check(Copies(Stored('first'),201172)==copies and Copies(Stored(1),201172)==copies
  and Stored(1).assignmentId==Stored('first').assignmentId,
  label..': the first-run target and its slot-1 handoff hold '..copies..' copies')
end

-- F1. Existing first-run plan: repeated saves in one open session.
FirstRunWorld()
for copies=2,4 do
 local last=Saved(201172,copies,'F1 save '..copies)
 check(last[2]==108,'F1: each save updates the plan mirror')
 FirstRunIs(copies,'F1 save '..copies)
end
check(Bound('first'),'F1: the open editor stays bound to the plan')
-- F2. Close and reopen, then save twice.
closeEditor();SlashCmdList.NEXUS('editor')
check(Ctx().name=='First plan' and Bound('first'),'F2: reopening opens the bound plan')
Saved(201172,5,'F2');FirstRunIs(5,'F2')
closeEditor()

-- F3. Switching plans: W-Free is saved without assignment; back on the
-- first-run plan, its saves update it again.
FirstRunWorld()
Saved(201172,2,'F3 first');FirstRunIs(2,'F3 first')
NexusWishlistEditorSwitchButton:Click();menuRow('W-Free'):Click()
check(Ctx().name=='W-Free','F3: W-Free is open')
Saved(201174,2,'F3 W-Free')
FirstRunIs(2,'F3 after W-Free');check(Stored('first').name=='First plan','F3: W-Free is not the first-run target')
NexusWishlistEditorSwitchButton:Click();menuRow('First plan'):Click()
check(Ctx().name=='First plan' and Bound('first'),'F3: back on the bound first-run plan')
Saved(201172,3,'F3 back');FirstRunIs(3,'F3 back')
Saved(201172,4,'F3 back again');FirstRunIs(4,'F3 back again')
closeEditor()

-- F4. A failed save writes nothing and keeps the binding; the next save
-- in the same session updates the plan.
FirstRunWorld()
local submit=H.service.UploadServerBuildSlot
H.service.UploadServerBuildSlot=function() return false end
local before=Uploads()
selected(201172).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup()
check(Uploads()==before,'F4: the refused upload is not recorded')
FirstRunIs(1,'F4 refused');check(Bound('first'),'F4: the binding is unchanged')
H.service.UploadServerBuildSlot=submit
Saved(201172,3,'F4 next');FirstRunIs(3,'F4 next')
-- F5. A save held by the service spacing guard is retried; the retried
-- save and the next one both update the plan.
local n0=Uploads()
selected(201172).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup()
local n1,l1=Uploads()
check(n1==n0+1 and Sent(l1,201172)==4,'F5 setup: an immediate save')
selected(201172).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup()
check(Uploads()==n1,'F5: the next save waits for the spacing guard')
H.Advance(4)
local n2,l2=Uploads()
check(n2==n1+1 and Sent(l2,201172)==5,'F5: the retry uploads the held save')
MirrorAt(108,l2);FirstRunIs(5,'F5 retried');check(Bound('first'),'F5: still bound after the retry')
closeEditor()

-- F6. Explicit Unassign between two saves stays authoritative.
FirstRunWorld()
Saved(201172,2,'F6 first');FirstRunIs(2,'F6 first')
check(A.ClearFirstRunWishlist(),'F6: explicit Unassign')
Saved(201172,3,'F6 stale')
check(Stored('first')==false and Stored(1)==nil,'F6: the stale save does not undo the Unassign')
Saved(201172,4,'F6 stale again')
check(Stored('first')==false and Stored(1)==nil,'F6: nor does a later save')
closeEditor();SlashCmdList.NEXUS('editor')
check(Ctx().name==nil,'F6: reopening opens a new draft, not the unassigned plan')
closeEditor()

-- F7. The Journal picker selects W-Free as the first-run plan between two
-- saves: that choice stays.
FirstRunWorld()
Saved(201172,2,'F7 first')
check(A.SetFirstRunWishlist(107),'F7: W-Free selected as the first-run plan')
local free,handoff=Assignment(1),Stored('first')
check(handoff.name=='W-Free' and free and free.name=='W-Free','F7 setup: W-Free with its handoff')
Saved(201172,3,'F7 stale')
check(Stored('first').name=='W-Free' and Copies(Stored('first'),201174)==1 and Same(Assignment(1),free),
 'F7: the stale save leaves the selected W-Free and its handoff')
closeEditor()

-- F8. Saved Build 1 is explicitly given W-Free between two saves.
FirstRunWorld({[1]={name='One',verified=true,echoes=E6},[107]={name='W-Free',verified=false,echoes=EF}})
check(Stored(1) and Stored(1).name=='First plan','F8 setup: the empty slot 1 holds the first-run handoff')
Saved(201172,2,'F8 first');FirstRunIs(2,'F8 first')
check(A.SetLoadoutWishlist(1,107),'F8: Saved Build 1 explicitly given W-Free')
local one=Assignment(1)
Saved(201172,3,'F8 stale')
check(Same(Assignment(1),one) and Copies(Stored(1),201174)==1 and not Stored('first'),
 'F8: slot 1 keeps W-Free; the stale save restores no first-run plan')
closeEditor()

-- F9. A key-only plan saved before assignment identities: the first save
-- is proven by its key, the next by the identity that save stamped. Its
-- slot-1 copy has no identity, so it is not a proven handoff and is kept.
Boot({maxSlots=6,active=0,slots={[108]={name='Legacy plan',verified=false,echoes=E1}}})
check(A.SetFirstLoadoutWishlistIdentity('Legacy plan',H.Clone(E1)),'F9 setup: plan')
check(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)
 s.firstRunWishlist.assignmentId=nil;s.loadoutWishlists[1].assignmentId=nil end),'F9 setup: identities removed')
H.Notify();A.Poll();H.Advance(1)
SlashCmdList.NEXUS('editor')
check(Ctx().name=='Legacy plan' and Ctx().assignmentId==nil,'F9: the key-only plan is open')
local legacySlot1=Assignment(1)
Saved(201172,2,'F9 first')
check(Copies(Stored('first'),201172)==2 and Bound('first'),'F9: the first save updates the plan and binds its identity')
Saved(201172,3,'F9 second')
check(Copies(Stored('first'),201172)==3 and Bound('first'),'F9: the second save in the same session updates it too')
check(Same(Assignment(1),legacySlot1),'F9: the unproven slot-1 copy is kept')
closeEditor()

-- N1. A new plan: Create binds nothing. A second Create in the same open
-- editor is a second new plan, as after close and reopen.
Boot({maxSlots=6,active=0,slots={}})
SlashCmdList.NEXUS('editor')
local c,l=CreatePlan('First plan',201172);MirrorAt(108,l)
check(Ctx().name==nil and Stored('first').name=='First plan','N1: the created plan is the first-run target; the editor still creates')
c,l=CreatePlan('Second plan',201174);MirrorAt(109,l)
check(l[2]==0 and Stored('first').name=='Second plan' and Stored(1).name=='Second plan','N1: the second Create is a new plan with the proven handoff')
closeEditor()

-- L1. Saved Build 6 of 6: repeated saves in one session update only slot 6.
one=LoadoutWorld()
for copies=2,4 do
 local last=Saved(201173,copies,'L1 save '..copies)
 check(last[2]==106 and Copies(Stored(6),201173)==copies and Stored(6).name=='W-Six','L1 save '..copies..': slot 6 holds the saved contents')
 check(Bound(6) and Same(Assignment(1),one) and not Stored('first'),'L1: bound; slot 1 and the first-run plan unchanged')
end
-- L2. Saved Build 6 given W-Free in the Journal while W-Six is open.
check(A.SetLoadoutWishlist(6,107),'L2: Saved Build 6 explicitly given W-Free')
local six=Assignment(6)
local heard,realPrint={},print
print=function(...) heard[#heard+1]=table.concat({tostring((...))},' ');realPrint(...) end
local last=Saved(201173,5,'L2 stale')
print=realPrint
local said=table.concat(heard,' / ')
check(said:find('that choice is kept',1,true) and not said:find('assignment failed',1,true),'L2: the save reports success and keeps the newer choice: '..said)
check(last[2]==106,'L2: the stale save still updates the W-Six server Wishlist')
check(Same(Assignment(6),six) and Copies(Stored(6),201174)==1,'L2: Saved Build 6 keeps W-Free')
check(Same(Assignment(1),one) and not Stored('first'),'L2: slot 1 and the first-run plan unchanged')
-- L3. Reopening shows the newer choice; its saves update it.
closeEditor();SlashCmdList.NEXUS('editor')
check(Ctx().loadoutSlot==6 and Ctx().name=='W-Free' and Bound(6),'L3: reopening opens W-Free for Saved Build 6')
last=Saved(201174,2,'L3')
check(last[2]==107 and Copies(Stored(6),201174)==2 and Bound(6),'L3: Saved Build 6 holds the saved W-Free')
Saved(201174,3,'L3 again');check(Copies(Stored(6),201174)==3,'L3: and the next save in the session')
closeEditor()
-- L4. Saved Build 6 unassigned while W-Six is open.
one=LoadoutWorld()
check(A.ClearLoadoutWishlist(6),'L4: explicit Unassign of Saved Build 6')
Saved(201173,2,'L4 stale')
check(Stored(6)==nil and Same(Assignment(1),one) and not Stored('first'),'L4: the stale save does not undo the Unassign')
closeEditor()
-- L5. A failed save keeps the binding; the next save updates slot 6.
one=LoadoutWorld()
submit=H.service.UploadServerBuildSlot
H.service.UploadServerBuildSlot=function() return false end
selected(201173).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup()
check(Copies(Stored(6),201173)==1 and Bound(6),'L5: a refused save writes nothing')
H.service.UploadServerBuildSlot=submit
Saved(201173,3,'L5 next');check(Copies(Stored(6),201173)==3 and Bound(6) and Same(Assignment(1),one),'L5: the next save updates slot 6 only')
closeEditor()
-- L6. A key-only Saved Build assignment: proven by key, then by identity.
Boot({maxSlots=6,active=6,slots=Slots6()})
Assign(6,'W-Six',E6)
check(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s) s.loadoutWishlists[6].assignmentId=nil end),'L6 setup: identity removed')
H.Notify();A.Poll();H.Advance(1)
SlashCmdList.NEXUS('editor')
check(Ctx().name=='W-Six' and Ctx().assignmentId==nil,'L6: the key-only assignment is open')
Saved(201173,2,'L6 first');check(Copies(Stored(6),201173)==2 and Bound(6),'L6: the first save updates it and binds')
Saved(201173,3,'L6 second');check(Copies(Stored(6),201173)==3 and Bound(6),'L6: the second save updates it too')
closeEditor()
-- L7. A Wishlist opened explicitly for Saved Build 6 (the Journal picker's
-- editor path): its save assigns it there, as before.
local function Candidate(slot) for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==slot then return c end end end
one=LoadoutWorld();closeEditor()
check(Nexus.WishlistEditor.OpenForWishlist(Candidate(107),6) and Ctx().name=='W-Free' and Ctx().loadoutSlot==6,'L7: W-Free opened for Saved Build 6')
Saved(201174,2,'L7')
check(Stored(6).name=='W-Free' and Copies(Stored(6),201174)==2 and Bound(6) and Same(Assignment(1),one),'L7: the save assigns W-Free to Saved Build 6 only')
Saved(201174,3,'L7 again');check(Copies(Stored(6),201174)==3,'L7: and the next save in the session updates it')
closeEditor()
-- L8. The same explicit open; Saved Build 6 is unassigned before the save.
one=LoadoutWorld();closeEditor()
check(Nexus.WishlistEditor.OpenForWishlist(Candidate(107),6),'L8: W-Free opened for Saved Build 6')
check(A.ClearLoadoutWishlist(6),'L8: explicit Unassign of Saved Build 6')
Saved(201174,2,'L8 stale')
check(Stored(6)==nil and Same(Assignment(1),one),'L8: the stale save does not assign W-Free')
closeEditor()
-- Chat notices printed while fn runs.
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return table.concat(heard,' / ')
end
-- L9. The oldest assignment shapes (a bare server slot; a record without a
-- key) are re-recorded by a save, with no false "choice is kept" notice.
for _,shape in ipairs({'bare slot','record without key'}) do
 Boot({maxSlots=6,active=6,slots=Slots6()})
 check(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)
  s.loadoutWishlists=s.loadoutWishlists or {}
  if shape=='bare slot' then s.loadoutWishlists[6]=106 else s.loadoutWishlists[6]={slot=106,name='W-Six'} end
 end),'L9 setup: '..shape)
 H.Notify();A.Poll();H.Advance(1)
 SlashCmdList.NEXUS('editor')
 check(Ctx().name=='W-Six' and Ctx().loadoutSlot==6,'L9 '..shape..': W-Six is open')
 local said=Heard(function() Saved(201173,2,'L9 '..shape) end)
 check(not said:find('that choice is kept',1,true),'L9 '..shape..': no false notice')
 check(type(Stored(6))=='table' and Stored(6).name=='W-Six' and Copies(Stored(6),201173)==2 and Bound(6),'L9 '..shape..': the save is recorded on Saved Build 6')
 Saved(201173,3,'L9 '..shape..' again');check(Copies(Stored(6),201173)==3,'L9 '..shape..': and the next save')
 closeEditor()
end
-- L10. The same W-Six chosen again for Saved Build 6 while it is open
-- (directly, or after an Unassign): that choice receives the save and the
-- plan stays editable.
for _,variant in ipairs({'re-pick','Unassign then re-pick'}) do
 one=LoadoutWorld()
 Saved(201173,2,'L10 '..variant..' first')
 if variant=='Unassign then re-pick' then check(A.ClearLoadoutWishlist(6),'L10: Unassign') end
 check(A.SetLoadoutWishlist(6,106),'L10 '..variant..': W-Six chosen again')
 local said=Heard(function() Saved(201173,3,'L10 '..variant) end)
 check(not said:find('that choice is kept',1,true),'L10 '..variant..': no false notice')
 check(Stored(6).name=='W-Six' and Copies(Stored(6),201173)==3 and Bound(6) and Same(Assignment(1),one),'L10 '..variant..': Saved Build 6 holds the saved W-Six')
 local linked=A.GetLoadoutWishlist(6)
 check(linked and linked.slot==106 and not linked.mirrorUnavailable,'L10 '..variant..': the assignment still resolves to its server Wishlist')
 closeEditor();SlashCmdList.NEXUS('editor')
 Saved(201173,4,'L10 '..variant..' reopened')
 check(Copies(Stored(6),201173)==4,'L10 '..variant..': the reopened plan saves')
 closeEditor()
end
-- L11. A save held by the spacing guard; Saved Build 6 is given W-Free
-- before the retry: the retry uploads, W-Free is kept, the save succeeds.
one=LoadoutWorld()
Saved(201173,2,'L11 first')
selected(201173).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup()
local u1=Uploads()
selected(201173).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup()
check(Uploads()==u1 and Nexus.WishlistEditor.IsApplyPending(),'L11: the next save waits for the spacing guard')
check(A.SetLoadoutWishlist(6,107),'L11: Saved Build 6 given W-Free')
six=Assignment(6)
local said=Heard(function() H.Advance(4) end)
local u2,l2=Uploads()
check(u2==u1+1 and l2[2]==106 and Sent(l2,201173)==4,'L11: the retry uploads W-Six')
check(said:find('that choice is kept',1,true) and not said:find('assignment failed',1,true) and not Nexus.WishlistEditor.IsApplyPending(),'L11: the retried save succeeds and says so')
check(Same(Assignment(6),six) and Same(Assignment(1),one),'L11: Saved Build 6 keeps W-Free; slot 1 unchanged')
closeEditor()
-- L12. A first-run plan chosen while a Saved Build editor is open (the
-- player switched to an empty Saved Build) is kept by its save. Control:
-- a first-run plan that existed before the editor opened is ended by the
-- save, as before.
LoadoutWorld()
H.perks.serverActiveSlot=3;H.Notify();A.Poll();H.Advance(1)
check(A.SetFirstRunWishlist(107),'L12: W-Free chosen as the first-run plan')
local chosen=Stored('first')
Saved(201173,2,'L12')
check(Stored('first') and Stored('first').assignmentId==chosen.assignmentId and Copies(Stored(6),201173)==2,'L12: the save updates Saved Build 6 and keeps the first-run choice')
Saved(201173,3,'L12 again')
check(Stored('first') and Stored('first').assignmentId==chosen.assignmentId,'L12: so does the next save')
closeEditor()
Boot({maxSlots=6,active=6,slots=Slots6()})
Assign(6,'W-Six',E6);check(A.SetFirstRunWishlist(107),'L12 control setup: an earlier first-run plan')
H.Notify();A.Poll();H.Advance(1)
SlashCmdList.NEXUS('editor')
Saved(201173,2,'L12 control')
check(Stored('first')==nil and Copies(Stored(6),201173)==2,'L12 control: the earlier first-run plan is ended, as before')
closeEditor()
print('PASS wishlist editor binding checks='..checks)
