-- Wishlist editor save safety (BN-WISHLIST-SAVE-SAFETY-005, ledger W1/W7).
-- A save without a loadout context used the first-run writer, which replaces
-- the slot-1 assignment and the first-run plan. Two ways in:
--   W7: the editor opened an active Saved Build above slot 5 as if no slot
--       were active, although the server declares that slot (maxSlots);
--   W1: saving an unassigned Wishlist chosen in the editor's switch menu.
-- Required: opening selects the active Saved Build the server declares;
-- saving changes only the edited Wishlist's own assignment; slot 1 is never
-- replaced unless it holds nothing or the proven first-run handoff; an
-- unassigned Wishlist saved while a Saved Build is active assigns nothing;
-- the first-run plan is the target exactly when the Echo Journal shows it
-- (no active Saved Build in the declared range, or an empty one) or when the
-- opened Wishlist is that plan; unknown slot data assigns nothing.
-- Synthetic server and mirrors only; real editor, controller and adapter.
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

-- 1. W7: the server declares 6 Saved Builds; slot 6 is active and assigned.
Boot({maxSlots=6,active=6,slots=Slots6()})
Assign(1,'W-One',E1);Assign(6,'W-Six',E6);H.Notify();A.Poll();H.Advance(1)
local one,six,first=Assignment(1),Assignment(6),FirstRun()
check(one and one.name=='W-One' and six and six.name=='W-Six' and first==nil,'fixture: distinct assignments for 1 and 6, no first-run plan')
SlashCmdList.NEXUS('editor')
check(Ctx().loadoutSlot==6 and Ctx().name=='W-Six','opening the editor selects active Saved Build 6 and its Wishlist (got slot '..tostring(Ctx().loadoutSlot)..', "'..tostring(Ctx().name)..'")')
local n,last=SaveEdit(201173)
check(n==1 and last[2]==106,'one upload to the edited Wishlist W-Six')
Mirror(106,'W-Six',last[4])
check(Same(Assignment(1),one),'saving slot 6 leaves the slot-1 assignment unchanged')
check(FirstRun()==nil,'saving slot 6 creates no first-run plan')
check(Assignment(6) and Assignment(6).name=='W-Six' and Assignment(6).key~=six.key,'slot 6 keeps its assignment with the edited contents')
-- Repeated save of the same editor session.
local six2=Assignment(6)
n,last=SaveEdit(201173);Mirror(106,'W-Six',last[4])
check(n==2 and last[2]==106 and Same(Assignment(1),one) and FirstRun()==nil,'a second save also touches only slot 6')
check(Assignment(6).key~=six2.key,'the second save updates slot 6 again')
-- The active Saved Build changes while the editor is open: the save still
-- belongs to the Wishlist that was opened (slot 6), not to slot 1.
H.perks.serverActiveSlot=1;H.Notify();A.Poll();H.Advance(1)
local six3=Assignment(6)
n,last=SaveEdit(201173);Mirror(106,'W-Six',last[4])
check(last[2]==106 and Same(Assignment(1),one) and FirstRun()==nil,'after the active slot changes, the open edit still saves only slot 6')
check(Assignment(6).key~=six3.key,'slot 6 receives that edit')
closeEditor()
-- A closed editor with an unsaved edit writes nothing.
H.perks.serverActiveSlot=6;H.Notify();A.Poll();H.Advance(1)
local before=H.Clone(Nexus.Store.State());local uploads=Uploads()
SlashCmdList.NEXUS('editor');selected(201173).plus:Click();closeEditor();H.Advance(1)
check(Uploads()==uploads and Same(Assignment(1),one) and Same(Assignment(6),{name=before.loadoutWishlists[6].name,key=before.loadoutWishlists[6].key,id=before.loadoutWishlists[6].assignmentId}),
 'closing without Save uploads and assigns nothing')

-- 2. W1: an unassigned Wishlist chosen in the switch menu (default server).
local slots5={[1]={name='One',verified=true,echoes=E1},[2]={name='Two',verified=true,echoes=E6},
 [101]={name='W-One',verified=false,echoes=E1},[107]={name='W-Free',verified=false,echoes=EF}}
Boot({maxSlots=5,active=1,slots=slots5})
Assign(1,'W-One',E1);H.Notify();A.Poll();H.Advance(1)
one,first=Assignment(1),FirstRun()
SlashCmdList.NEXUS('editor')
check(Ctx().loadoutSlot==1 and Ctx().name=='W-One','fixture: the editor opens slot 1 (W-One)')
NexusWishlistEditorSwitchButton:Click()
menuRow('W-Free'):Click()
check(Ctx().name=='W-Free' and Ctx().loadoutSlot==nil,'the unassigned Wishlist W-Free is open, with no Saved Build')
n,last=SaveEdit(201174)
check(n==1 and last[2]==107,'one upload to W-Free')
Mirror(107,'W-Free',last[4])
check(Same(Assignment(1),one),'saving an unassigned Wishlist leaves the slot-1 assignment unchanged')
check(FirstRun()==nil and Assignment(2)==nil,'saving an unassigned Wishlist creates no first-run plan and no other assignment')
closeEditor()

-- 3. An active slot the server does not declare (7 of 6) and missing
-- slot-count data (6 of the fallback 5): the first-run plan is the target
-- (as the Journal shows it), but the populated slot 1 keeps its assignment.
for _,case in ipairs({{name='active 7 of 6',maxSlots=6,active=7},{name='no slot count',maxSlots=false,active=6}}) do
 local rows=Slots6();rows[7]={name='Seven',verified=true,echoes=EF}
 Boot({maxSlots=case.maxSlots,active=case.active,slots=rows})
 Assign(1,'W-One',E1);H.Notify();A.Poll();H.Advance(1)
 one=Assignment(1)
 SlashCmdList.NEXUS('editor')
 check(Ctx().loadoutSlot==nil and Ctx().name==nil,'case '..case.name..': a new draft opens, not slot 1')
 local c,l=CreatePlan('New plan',201174)
 check(c==1,'case '..case.name..': the new plan is uploaded (not vacuous)')
 Mirror(l[2],l[3],l[4])
 check(Same(Assignment(1),one),'case '..case.name..': slot 1 keeps its assignment')
 check(FirstRun() and FirstRun().name=='New plan','case '..case.name..': the new plan is the first-run target')
 check(Assignment(6)==nil and Assignment(7)==nil,'case '..case.name..': no other slot is assigned as a fallback')
end

-- 3b. No active Saved Build while Saved Builds exist (death/reset, or saved
-- but not activated): Create sets the first-run plan; slot 1 is not replaced.
Boot({maxSlots=5,active=1,slots=slots5})
Assign(1,'W-One',E1);H.Notify();A.Poll();H.Advance(1)
one=Assignment(1)
H.perks.serverActiveSlot=0;H.Notify();A.Poll();H.Advance(1)
SlashCmdList.NEXUS('editor')
local c3,l3=CreatePlan('Reset plan',201174);check(c3==1,'3b: uploaded');Mirror(l3[2],l3[3],l3[4])
check(Same(Assignment(1),one) and FirstRun() and FirstRun().name=='Reset plan','3b: slot 1 kept; the new plan is the first-run target')
-- 3c. An unassigned Wishlist opened while slot 1 was active, saved after the
-- active slot became 0: slot 1 is not replaced.
Boot({maxSlots=5,active=1,slots=slots5})
Assign(1,'W-One',E1);H.Notify();A.Poll();H.Advance(1)
one=Assignment(1)
SlashCmdList.NEXUS('editor');NexusWishlistEditorSwitchButton:Click();menuRow('W-Free'):Click()
H.perks.serverActiveSlot=0;H.Notify();A.Poll();H.Advance(1)
n,last=SaveEdit(201174);Mirror(107,'W-Free',last[4])
check(Same(Assignment(1),one),'3c: slot 1 keeps W-One')
-- 3d. An empty active Saved Build in range: New Wishlist sets the first-run
-- plan, which the Journal and the HUD use for that slot; slot 1 (empty) gets
-- the handoff because it held nothing.
Boot({maxSlots=6,active=1,slots={[1]={name='One',verified=true,echoes={}},[101]={name='W-Old',verified=false,echoes=E1}}})
SlashCmdList.NEXUS('editor');button('+ New Wishlist'):Click()
local c4,l4=CreatePlan('Empty slot plan',201174);check(c4==1,'3d: uploaded');Mirror(l4[2],l4[3],l4[4])
check(FirstRun() and FirstRun().name=='Empty slot plan' and Assignment(1) and Assignment(1).name=='Empty slot plan','3d: first-run plan and its slot-1 handoff')
-- 3e. Slot data not loaded: a new plan is saved but nothing is assigned.
Boot({maxSlots=5,active=1,slots=slots5})
Assign(1,'W-One',E1);H.Notify();A.Poll();H.Advance(1)
one=Assignment(1)
H.perks.serverBuildSlots=nil;H.Notify();A.Poll();H.Advance(1)
SlashCmdList.NEXUS('editor')
local c5=CreatePlan('Unloaded plan',201174);check(c5==1,'3e: uploaded')
check(Same(Assignment(1),one) and FirstRun()==nil,'3e: unknown slot data: slot 1 and the first-run plan unchanged')

-- 4. Genuine first run: no active Saved Build yet; Create still hands off.
Boot({maxSlots=6,active=0,slots={}})
SlashCmdList.NEXUS('editor')
NexusWishlistNameInput:SetText('First plan')
for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==201172 then f:Click();break end end
button('Create Wishlist'):Click()
check(H.popup and H.popup.which=='WISHLISTREALIZER_CREATE_WISHLIST','first run: Create asks for confirmation')
H.AcceptPopup()
local c,l=Uploads()
check(c==1,'first run: one upload')
Mirror(l[2],l[3],l[4])
check(FirstRun() and FirstRun().name=='First plan' and Assignment(1) and Assignment(1).name=='First plan','first run: the plan is the first-run plan and the slot-1 handoff')
local planSlot
for slot,row in pairs(H.perks.serverBuildSlots) do if row.name=='First plan' then planSlot=slot end end
check(planSlot and planSlot>6,'fixture: the plan is mirrored in a designed slot above the declared range: '..tostring(planSlot))
closeEditor()
-- M1-C: the active slot number is that designed slot, as in a reported
-- profile. Editing the first-run plan updates it and its proven handoff.
local before4=FirstRun()
H.perks.serverActiveSlot=planSlot;H.Notify();A.Poll();H.Advance(1)
SlashCmdList.NEXUS('editor')
check(Ctx().name=='First plan' and Ctx().loadoutSlot==nil,'M1-C: the first-run plan opens')
n,last=SaveEdit(201172);Mirror(last[2],last[3],last[4])
check(FirstRun().key~=before4.key and Same(Assignment(1),FirstRun()),'M1-C: the first-run plan and its handoff receive the edit')
closeEditor()
-- M1-E: opened with no active Saved Build, then Saved Build 1 becomes
-- active before Save: the save still belongs to the opened first-run plan.
H.perks.serverActiveSlot=0;H.Notify();A.Poll();H.Advance(1)
local before5=FirstRun()
SlashCmdList.NEXUS('editor')
check(Ctx().name=='First plan','M1-E: the first-run plan opens')
local rows=H.Clone(H.perks.serverBuildSlots);rows[1]={name='One',verified=true,echoes=H.Clone(E1)}
H.perks.serverBuildSlots=rows;H.perks.serverActiveSlot=1;H.Notify();A.Poll();H.Advance(1)
n,last=SaveEdit(201172);Mirror(last[2],last[3],last[4])
check(FirstRun().key~=before5.key and Same(Assignment(1),FirstRun()),'M1-E: the opened first-run plan and its handoff receive the edit')
print('PASS wishlist save slot safety checks='..checks)
