-- Assignment action tokens (BN-CONTROL-FULL-REVIEW-20261001-005-CORRECTION-02).
-- test.9058 let a stale editor overwrite an explicit Restore: open A,
-- Unassign (A retained), choose A again, save B, Unassign, Restore A, save C
-- replaced A, because A's contents were "held" by the editor. Required: one
-- opaque token per assignment destination (each Saved Build, the first-run
-- plan), replaced by every Assign, Unassign and Restore (also of the same
-- plan, also of an empty destination), bound when the editor opens; a save
-- writes a destination only while its token is unchanged and adopts only the
-- tokens it installed; the first-run plan and the slot-1 handoff are checked
-- independently; tokens start over on an owner or database rebind.
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
-- Chat notices printed while fn runs.
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return table.concat(heard,' / ')
end
-- Press Save in an editor whose destination was assigned, unassigned or
-- restored meanwhile: nothing is uploaded or assigned, the notice says why,
-- and the edits stay in the editor.
-- Copies of one Echo in the editor's draft (its own controller).
local function DraftCopies(id)
 local show=Nexus.WishlistEditor.Show
 for i=1,255 do local n,v=debug.getupvalue(show,i);if not n then break end
  if n=='wishlistController' then return Copies({echoes=v.CanonicalEchoes()},id) end end
 error('editor controller not found')
end
local function Refused(id,label)
 local before,pending=Uploads(),DraftCopies(id)
 local said=Heard(function() selected(id).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup() end)
 check(Uploads()==before,label..': nothing is uploaded')
 check(said:find('Not saved:',1,true) and said:find('that choice is kept',1,true)
  and not said:find('assignment failed',1,true),label..': the notice says why: '..said)
 check(DraftCopies(id)==pending+1 and not Nexus.WishlistEditor.IsApplyPending(),
  label..': the edits stay in the editor; nothing is pending')
 return said
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

local function Token(destination) return A.AssignmentActionToken(destination) end
local function BoundToken(destination)
 local b=Ctx().boundActions;local key=destination=='first' and 'first' or tonumber(destination)
 return b and (b.tokens[key] or ('e'..tostring(b.epoch)..':0')) or nil
end
local function Rec(slot) local r=Stored(slot);return r and {name=r.name,key=r.key,id=r.assignmentId} or r end
local function SameRec(a,b) return type(a)=='table' and type(b)=='table' and a.name==b.name and a.key==b.key and a.id==b.id end

-- T1. The control's sequence: open A; Unassign (A retained); choose A again;
-- save B in the same editor; Unassign; Restore the retained A; save C.
one=LoadoutWorld()
local A0=Rec(6)
local t=Token(6)
check(A.ClearLoadoutWishlist(6) and Token(6)~=t,'T1: Unassign replaces the token')
t=Token(6)
check(A.SetLoadoutWishlist(6,106) and Token(6)~=t,'T1: choosing the same A again replaces the token')
local A1=Rec(6)
Refused(201173,'T1 save B')
check(SameRec(Rec(6),A1) and Copies(Stored(6),201173)==1,'T1: the chosen A is kept, unchanged')
check(A.ClearLoadoutWishlist(6),'T1: Unassign')
t=Token(6)
check(A.RestoreForgottenWishlistPlan({assignmentId=A0.id}) and SameRec(Rec(6),A0) and Token(6)~=t,'T1: Restore puts back the retained A and replaces the token')
Refused(201173,'T1 save C')
check(SameRec(Rec(6),A0) and Copies(Stored(6),201173)==1 and Same(Assignment(1),one),'T1: the restored A survives (identity and contents)')
closeEditor();SlashCmdList.NEXUS('editor')
check(Ctx().name=='W-Six' and BoundToken(6)==Token(6),'T1: the reopened editor binds the current token')
Saved(201173,2,'T1 reopened')
check(Copies(Stored(6),201173)==2 and BoundToken(6)==Token(6),'T1: and saves, adopting the token its save installed')
closeEditor()

-- T2. ABA: Unassign, then Restore the exact original identity and contents.
one=LoadoutWorld()
local X=Rec(6)
check(A.ClearLoadoutWishlist(6) and A.RestoreForgottenWishlistPlan({assignmentId=X.id}) and SameRec(Rec(6),X),'T2: the exact original is back')
check(BoundToken(6)~=Token(6),'T2: its token is not the one the editor bound')
Refused(201173,'T2 stale')
check(SameRec(Rec(6),X) and Copies(Stored(6),201173)==1,'T2: the restored original survives')
closeEditor()

-- T3. Restore contents this editor saved itself.
one=LoadoutWorld()
Saved(201173,2,'T3 save B')
local B=Rec(6)
check(A.ClearLoadoutWishlist(6) and A.RestoreForgottenWishlistPlan({assignmentId=B.id}) and SameRec(Rec(6),B),'T3: the saved B is restored')
Refused(201173,'T3 stale')
check(SameRec(Rec(6),B) and Copies(Stored(6),201173)==2,'T3: the restored B survives')
closeEditor()

-- T4. First-run editing; Saved Build 1 is acted on independently.
-- T4a: the slot-1 handoff is unassigned: the first-run plan still saves;
-- slot 1 stays unassigned.
FirstRunWorld()
check(A.ClearLoadoutWishlist(1) and Stored(1)==nil,'T4a: slot-1 handoff unassigned')
local first0=Token('first')
Saved(201172,2,'T4a save')
check(Copies(Stored('first'),201172)==2 and Stored(1)==nil,'T4a: the first-run plan saves; slot 1 stays unassigned')
check(Token('first')~=first0 and BoundToken('first')==Token('first') and BoundToken(1)~=Token(1),'T4a: the editor adopts the first-run token only')
Saved(201172,3,'T4a again')
check(Copies(Stored('first'),201172)==3 and Stored(1)==nil,'T4a: and again')
closeEditor()
-- T4b: an Unassign of an EMPTY slot 1 also counts.
FirstRunWorld()
check(A.ClearLoadoutWishlist(1),'T4b setup: slot 1 emptied')
closeEditor();SlashCmdList.NEXUS('editor')
check(Ctx().name=='First plan' and Stored(1)==nil,'T4b: the first-run plan is open; slot 1 is empty')
t=Token(1)
check(A.ClearLoadoutWishlist(1) and Token(1)~=t,'T4b: Unassign of the empty slot 1 replaces its token')
Saved(201172,2,'T4b save')
check(Copies(Stored('first'),201172)==2 and Stored(1)==nil,'T4b: the first-run save does not fill slot 1')
closeEditor()
-- T4c control: no slot-1 action: the handoff follows, as before.
FirstRunWorld()
Saved(201172,2,'T4c save');FirstRunIs(2,'T4c')
check(BoundToken(1)==Token(1) and BoundToken('first')==Token('first'),'T4c: the editor adopts both installed tokens')
closeEditor()

-- T5. Token evolution: every explicit action replaces the token; a refused
-- upload or a save held by the spacing guard does not; a save installs one.
one=LoadoutWorld()
t=Token(6)
local submit=H.service.UploadServerBuildSlot
H.service.UploadServerBuildSlot=function() return false end
selected(201173).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup()
H.service.UploadServerBuildSlot=submit
check(Token(6)==t and BoundToken(6)==t,'T5: a refused upload keeps the token')
Saved(201173,3,'T5 save')
check(Token(6)~=t and BoundToken(6)==Token(6),'T5: a save installs a token and the editor adopts it')
t=Token(6)
selected(201173).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup()
check(Token(6)~=t and BoundToken(6)==Token(6) and Copies(Stored(6),201173)==4,'T5: an immediate save installs a token and the editor adopts it')
t=Token(6)
selected(201173).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup()
check(Nexus.WishlistEditor.IsApplyPending() and Token(6)==t,'T5: a save held by the spacing guard keeps the token')
H.Advance(4)
local _,l5=Uploads();Mirror(l5[2],l5[3],l5[4])
check(not Nexus.WishlistEditor.IsApplyPending() and Token(6)~=t and BoundToken(6)==Token(6) and Copies(Stored(6),201173)==5,'T5: the retried save installs and adopts a token')
closeEditor()
local actions={
 {'Assign',function() return A.SetLoadoutWishlist(6,107) end,6},
 {'same-plan Assign',function() return A.SetLoadoutWishlist(6,107) end,6},
 {'Unassign',function() return A.ClearLoadoutWishlist(6) end,6},
 {'Unassign of empty',function() return A.ClearLoadoutWishlist(6) end,6},
 {'Restore',function() return A.RestoreForgottenWishlistPlan({}) end,6},
 {'Forget',function() return A.ForgetWishlistPlan({associationIndex=6}) end,6},
 {'first-run select',function() return A.SetFirstRunWishlist(107) end,'first'},
 {'first-run Unassign',function() return A.ClearFirstRunWishlist() end,'first'},
}
for _,a in ipairs(actions) do
 local before=Token(a[3])
 check(a[2]() and Token(a[3])~=before,'T5: '..a[1]..' replaces the '..tostring(a[3])..' token')
end
local seen,dup={},false
for _,dest in ipairs({1,2,6,'first'}) do local v=Token(dest);if v:sub(-2)~=':0' then if seen[v] then dup=true end;seen[v]=true end end
check(not dup,'T5: tokens are never reused')

-- T6. Owner or database rebind: tokens start over; an editor bound before
-- it is stale; a reopened editor binds the new epoch.
for _,kind in ipairs({'database','owner'}) do
 one=LoadoutWorld()
 local epoch=Ctx().boundActions.epoch
 local realOwner=Nexus.Store.CurrentOwnerKey
 if kind=='database' then NexusDB=H.Clone(NexusDB)
 else Nexus.Store.CurrentOwnerKey=function() return 'other@realm' end end
 check(Token(6)=='e'..A.AssignmentActionSnapshot().epoch..':0' and A.AssignmentActionSnapshot().epoch~=epoch,'T6 '..kind..': a new epoch with fresh tokens')
 if kind=='owner' then Nexus.Store.CurrentOwnerKey=realOwner end
 Refused(201173,'T6 '..kind..' stale')
 check(Copies(Stored(6),201173)==1,'T6 '..kind..': nothing assigned')
 closeEditor();SlashCmdList.NEXUS('editor')
 check(Ctx().boundActions.epoch==A.AssignmentActionSnapshot().epoch,'T6 '..kind..': reopening binds the current epoch')
 Saved(201173,2,'T6 '..kind..' reopened')
 check(Copies(Stored(6),201173)==2,'T6 '..kind..': the reopened editor saves')
 closeEditor()
end

-- T7. Create is guarded the same way.
-- T7a: a new Wishlist for the unassigned Saved Build 6; Saved Build 6 is
-- given W-Free before Create.
Boot({maxSlots=6,active=6,slots=Slots6()})
Assign(1,'W-One',E1);H.Notify();A.Poll();H.Advance(1)
SlashCmdList.NEXUS('editor')
check(Ctx().name==nil,'T7a: a new draft for Saved Build 6')
check(A.SetLoadoutWishlist(6,107),'T7a: Saved Build 6 given W-Free')
local before7=Uploads()
NexusWishlistNameInput:SetText('Late plan')
for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==201172 then f:Click();break end end
local said7=Heard(function() button('Create Wishlist'):Click();H.AcceptPopup() end)
check(Uploads()==before7 and said7:find('Not saved:',1,true) and Stored(6).name=='W-Free','T7a: Create uploads nothing and W-Free stays')
closeEditor()
-- T7b: a new first-run plan; the Journal picks W-Free as the first-run plan
-- before Create.
Boot({maxSlots=6,active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
SlashCmdList.NEXUS('editor')
check(A.SetFirstRunWishlist(107),'T7b: W-Free chosen as the first-run plan')
before7=Uploads()
NexusWishlistNameInput:SetText('Late first plan')
for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==201172 then f:Click();break end end
said7=Heard(function() button('Create Wishlist'):Click();H.AcceptPopup() end)
check(Uploads()==before7 and said7:find('Not saved:',1,true) and Stored('first').name=='W-Free','T7b: Create uploads nothing and W-Free stays the first-run plan')
closeEditor()
-- T7c control: Create, then Create again, in one editor (adopted tokens).
Boot({maxSlots=6,active=0,slots={}})
SlashCmdList.NEXUS('editor')
local c7,l7=CreatePlan('First plan',201172);MirrorAt(108,l7)
c7,l7=CreatePlan('Second plan',201174);MirrorAt(109,l7)
check(c7==2 and Stored('first').name=='Second plan' and Stored(1).name=='Second plan','T7c: both Creates are saved')
closeEditor()

-- T8. An action on another destination does not stop the save.
one=LoadoutWorld()
check(A.SetFirstRunWishlist(107),'T8: the first-run plan changed elsewhere')
Saved(201173,2,'T8 save')
check(Copies(Stored(6),201173)==2 and Stored('first') and Stored('first').name=='W-Free','T8: Saved Build 6 saves; the first-run choice stays')
check(BoundToken('first')~=Token('first') and BoundToken(6)==Token(6),'T8: the editor adopts only Saved Build 6')
closeEditor()

-- T9. The automatic promotion of the first-run plan to a newly active
-- Saved Build counts as a write to both destinations.
Boot({maxSlots=6,active=0,slots={[3]={name='Three',verified=true,echoes=E6}}})
SlashCmdList.NEXUS('editor')
local c9,l9=CreatePlan('First plan',201172);MirrorAt(108,l9);closeEditor()
SlashCmdList.NEXUS('editor')
check(Ctx().name=='First plan','T9: the first-run plan is open')
t=Token(3)
H.perks.serverActiveSlot=3;H.Notify();A.Poll();H.Advance(1)
A.Wishlist()
check(Stored(3) and Stored(3).name=='First plan' and Token(3)~=t,'T9: promoted to Saved Build 3; its token replaced')
Refused(201172,'T9 stale')
check(Stored(3).name=='First plan' and Copies(Stored(3),201172)==1,'T9: the promoted assignment is kept')
closeEditor()
-- T10. A destination changed while the upload is in flight (after the check
-- before the upload): each writer's own check inside the mutation keeps the
-- newer choice; the editor adopts nothing.
-- T10a: Saved Build 6 given W-Free during the upload.
one=LoadoutWorld()
local submit10=H.service.UploadServerBuildSlot
H.service.UploadServerBuildSlot=function(slot,name,entries)
 local ok=submit10(slot,name,entries)
 assert(A.SetLoadoutWishlist(6,107))
 return ok
end
local bound10=BoundToken(6)
local said10=Heard(function() selected(201173).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup() end)
H.service.UploadServerBuildSlot=submit10
check(said10:find('was uploaded, but its assignment',1,true) and not said10:find('assignment failed',1,true),'T10a: the save says the newer choice is kept: '..said10)
check(Stored(6).name=='W-Free' and Same(Assignment(1),one) and BoundToken(6)==bound10,'T10a: Saved Build 6 keeps W-Free; the editor adopts nothing')
closeEditor()
-- T10b: the same first-run plan forgotten and restored (same identity, new
-- token) during the upload.
FirstRunWorld()
local P10=Stored('first')
local submit10b=H.service.UploadServerBuildSlot
H.service.UploadServerBuildSlot=function(slot,name,entries)
 local ok=submit10b(slot,name,entries)
 assert(A.ForgetWishlistPlan({associationIndex=1}) and A.RestoreForgottenWishlistPlan({}))
 return ok
end
said10=Heard(function() selected(201172).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup() end)
H.service.UploadServerBuildSlot=submit10b
check(said10:find('was uploaded, but its assignment',1,true),'T10b: the save says the restored choice is kept: '..said10)
check(Stored('first').assignmentId==P10.assignmentId and Copies(Stored('first'),201172)==1
 and Stored(1) and Stored(1).assignmentId==P10.assignmentId,'T10b: the restored first-run plan and its handoff are kept')
closeEditor()

-- T11. ABA on the first-run plan: Forget and Restore bring back the same
-- identity while a Saved Build editor is open; its save keeps the plan.
Boot({maxSlots=6,active=6,slots=Slots6()})
Assign(6,'W-Six',E6)
check(A.SetFirstLoadoutWishlistIdentity('Plan P',H.Clone(E1)),'T11 setup: a first-run plan with its slot-1 handoff')
H.Notify();A.Poll();H.Advance(1)
local P=Stored('first')
SlashCmdList.NEXUS('editor')
check(Ctx().loadoutSlot==6,'T11: Saved Build 6 is open')
check(A.ForgetWishlistPlan({associationIndex=1}) and not Stored('first'),'T11: Forget removes the handoff and the first-run pointer')
check(A.RestoreForgottenWishlistPlan({}) and Stored('first') and Stored('first').assignmentId==P.assignmentId,'T11: Restore brings back the same identity')
Saved(201173,2,'T11 save')
check(Copies(Stored(6),201173)==2 and Stored('first') and Stored('first').assignmentId==P.assignmentId,'T11: Saved Build 6 saves; the restored first-run plan stays')
closeEditor()
print('PASS wishlist assignment action token checks='..checks)
