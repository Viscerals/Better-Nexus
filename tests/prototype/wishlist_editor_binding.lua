-- Wishlist editor binding across saves (BN-CONTROL-FULL-REVIEW-20261001-
-- 005-CORRECTION-01). A save stamps a new assignment identity; the open
-- editor kept the old one, so the second save of an existing first-run plan
-- in one session was no longer proven to be that plan's and its assignment
-- update was lost. Required: the editor's proven binding follows its own
-- successful save (the identity checks are unchanged); an explicit Unassign
-- or reassignment made while the editor is open stays authoritative. Each
-- row checks the uploaded contents and the stored first-run/slot assignment
-- contents.
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

print('PASS wishlist editor binding checks='..checks)
