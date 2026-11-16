-- W15: Journal "Edit wishlist" -> Save with an EMPTY positive active Saved Build.
-- The editor binds that slot as its destination. Saving used to upload, write an
-- unusable association under the empty slot and clear the first-run plan.
-- Synthetic service mirrors only; no real account or game access.
local T=dofile('tests/prototype/startup_support.lua')
local NAME='W15-PLAN'
local OTHER='W15-OTHER'
local checks=0
local function check(ok,msg) checks=checks+1; assert(ok,msg) end
local notices={}
local rawPrint=print
print=function(...)
 local parts={}
 for i=1,select('#',...) do parts[#parts+1]=tostring((select(i,...))) end
 notices[#notices+1]=table.concat(parts,' ')
end
local function said(fragment)
 for _,line in ipairs(notices) do if line:find(fragment,1,true) then return true end end
 return false
end
local function boot(saved,slots,active)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil
 local h=dofile('tests/prototype/harness.lua')
 local create=CreateFrame
 CreateFrame=function(kind,name,parent,template)
  local f=create(kind,name,parent,template)
  if template=='UIPanelCloseButton' then
   f._testTemplateClose=true
   f:SetScript('OnClick',function(self)self:GetParent():Hide()end)
  end
  return f
 end
 h.playerLevel=1
 wipe(h.db)
 h.AddEcho(201172,'Arcane Bombardment',0,5)
 h.AddEcho(200767,'Arcane Bond',0,5)
 h.perks.serverActiveSlot=active or 0
 h.perks.serverBuildSlots=slots or {}
 NexusDB=saved
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
  GetCharges=function()return 0 end,IsOfferPending=function()return false end,
  RequestCharges=function()end,
  ConfirmSpend=function()error('must not spend')end}
 h.Boot()
 return h
end
local H=boot()
-- Revision 6 (updated-client compatibility, full-CI finding): GameAdapter.
-- UploadWishlist replaces an existing server Wishlist (slot > 0) only when
-- the current slot list shows that destination in full; a missing one is
-- refused ("stale_slot") and starts no spacing. Slot 103 is not in this
-- fixture's list, so the spacing setup names it as a known synthetic Wishlist
-- mirror (above the declared slots, unverified, the spacer's own Echoes) for
-- that one real upload and then puts the list back exactly as it was. The
-- spacing window is the production one, opened by that real upload; nothing
-- is stubbed and no timestamp is set.
local function KnownSlotUpload(upload,slot,name,echoes)
 local created=H.perks.serverBuildSlots==nil
 if created then H.perks.serverBuildSlots={} end
 local slots=H.perks.serverBuildSlots
 local prior=slots[slot]
 local rows={}
 for i,e in ipairs(echoes) do rows[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks or 1,locked=false} end
 slots[slot]={name=name,verified=false,echoes=rows}
 local ok,why=upload(slot,name,echoes)
 slots[slot]=prior
 if created then H.perks.serverBuildSlots=nil end
 return ok,why
end
-- M3: the editor's actions are named by their effect; a legacy label also
-- finds the action with that default intent (new label first, then legacy).
local LABELS={['Create Wishlist']={'Create & assign','Create unassigned','Create Wishlist'},
 ['Save Wishlist']={'Save & assign','Save changes','Save Wishlist'}}
local function button(text)
 for _,label in ipairs(LABELS[text] or {text})do
  for _,f in ipairs(H.frames)do
   if f.kind=='Button' and f:IsVisible() and f:GetText()==label then return f end
  end
 end
 error('visible button absent: '..text)
end
local function catalog(id)
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==id then return f end
 end
 error('visible catalog row absent: '..id)
end
local function selected(id)
 for _,f in ipairs(H.frames)do
  if f:IsVisible() and f.plus and f.data and f.data.spellId==id then return f end
 end
 error('visible selected row absent: '..id)
end
local function journal()
 if not ProjectEbonholdEchoJournal then CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)end
 ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
end
local function snapshot() return H.Clone(Nexus.Store.State()) end
local function populated(slot)
 local row=Nexus.GameAdapter.Slots().bySlot[slot]
 return row~=nil and #row.echoes>0
end
-- The gear of the listed row `name`. The selector names the plan wherever it is
-- the selection, and the picker then does not list it: its Journal edit
-- control is the design button.
local function pickerGear(name)
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f.glyph and f:IsVisible() and f~=NexusAssociatedWishlistDesignButton then
   local row=f:GetParent()
   local label=row and row.nameButton and row.nameButton.text and row.nameButton.text:GetText() or ''
   if label:find(name,1,true) then return f end
  end
 end
 check(name==NAME and NexusActiveWishlistSelector.text:GetText():find(NAME,1,true),'picker gear absent: '..name)
 return NexusAssociatedWishlistDesignButton
end

-- A first-run plan made through the real editor (active slot 0 = no Saved Build).
journal();button('New Wishlist'):Click()
catalog(201172):Click()
local emptySlot
for _,f in ipairs(H.frames)do if f:IsVisible() and f.slotState=='empty' then emptySlot=f;break end end
emptySlot:Click();catalog(200767):Click()
_G.NexusWishlistNameInput:SetText(NAME)
button('Create Wishlist'):Click();H.AcceptPopup()
local mirror={[102]={name=NAME,verified=false,echoes=H.Clone(H.actions[1][4])}}
H.perks.serverBuildSlots=H.Clone(mirror);H.Notify();Nexus.GameAdapter.Poll();H.Advance(4)
local saved=H.Clone(NexusDB)

local function reopen(slot2,active)
 local slots=H.Clone(mirror)
 -- Another server Wishlist, equal contents in another slot: a distinct
 -- identity the picker lists beside the selected plan.
 slots[104]={name=OTHER,verified=false,echoes=H.Clone(mirror[102].echoes)}
 if slot2~=nil then slots[2]={name=slot2.name or '',verified=false,echoes=slot2.echoes} end
 H=boot(H.Clone(saved),slots,active or 2)
 notices={}
 return H
end
local function editViaPicker(name)
 journal()
 NexusActiveWishlistSelector:Click()
 pickerGear(name or NAME):Click()
 selected(201172).plus:Click()
end

-- 1. Empty active Saved Build + first-run plan, public picker gear, Save. The
-- selector names the first-run plan, so the gear is that of the other listed
-- Wishlist; it binds the empty Saved Build as its destination all the same.
reopen({echoes={}})
do
 local before=snapshot()
 check(before.firstRunWishlist and before.firstRunWishlist.key=='201172:1','precondition: a first-run plan exists')
 check(populated(2)==false,'precondition: active slot 2 is empty')
 editViaPicker(OTHER)
 button('Save Wishlist'):Click()
 check(H.popup==nil,'no confirmation is offered for a destination that cannot hold the Wishlist')
 check(#H.actions==0,'nothing is uploaded')
 check(T.Equal(before,snapshot()),'the first-run plan and every assignment are untouched')
 check(snapshot().loadoutWishlists[2]==nil,'no association is written under the empty slot')
 check(said('Saved Build 2 is empty') and said('Nothing was uploaded'),'the refusal is explained and says nothing was changed')
 check(pcall(selected,201172) and selected(201172).data.stacks==2,'the edited draft is still shown')
 -- the draft is kept: the same editor can still save once the slot has Echoes
 H.perks.serverBuildSlots[2].echoes={{spellId=200767,quality=0,stacks=1,locked=false}}
 button('Save Wishlist'):Click();H.AcceptPopup();H.Advance(4)
 check(#H.actions==1 and H.actions[1][1]=='upload' and H.actions[1][2]==104,'once the slot has Echoes the same draft saves')
 check(snapshot().loadoutWishlists[2] and snapshot().loadoutWishlists[2].key=='201172:2','and is assigned to that Saved Build')
end

-- 2. The slot empties AFTER the confirmation was offered.
reopen({echoes={{spellId=200767,quality=0,stacks=1,locked=false}}})
do
 local before=snapshot()
 editViaPicker()
 button('Save Wishlist'):Click()
 check(H.popup and H.popup.which=='WISHLISTREALIZER_UPDATE_WISHLIST','precondition: populated slot offers the confirmation')
 H.perks.serverBuildSlots[2].echoes={}
 H.AcceptPopup();H.Advance(4)
 check(#H.actions==0,'a destination emptied during the confirmation is not uploaded to')
 check(T.Equal(before,snapshot()),'and the previous assignments are kept')
end

-- 3. Populated Saved Build keeps the normal Save, including a locked-only build.
for _,case in ipairs({
 {tag='populated',echoes={{spellId=200767,quality=0,stacks=1,locked=false}}},
 {tag='locked-only',echoes={{spellId=200767,quality=0,stacks=1,locked=true}}},
})do
 reopen({echoes=case.echoes})
 check(populated(2)==true,case.tag..': the slot counts as populated')
 editViaPicker()
 button('Save Wishlist'):Click();H.AcceptPopup();H.Advance(4)
 local after=snapshot()
 check(#H.actions==1 and H.actions[1][2]==102,case.tag..': one upload')
 check(after.loadoutWishlists[2] and after.loadoutWishlists[2].key=='201172:2',case.tag..': assigned to the Saved Build')
 check(after.firstRunWishlist==nil,case.tag..': the first-run plan is superseded as before')
 check(Nexus.GameAdapter.GetLoadoutWishlist(2)~=nil,case.tag..': the assignment is usable')
end

-- 4. The explicit first-run route (Journal design button) is unchanged on an empty slot.
reopen({echoes={}})
do
 journal()
 check(NexusAssociatedWishlistDesignButton:IsEnabled(),'the design button is enabled for the first-run plan')
 NexusAssociatedWishlistDesignButton:Click()
 selected(201172).plus:Click()
 button('Save Wishlist'):Click();H.AcceptPopup();H.Advance(4)
 local after=snapshot()
 check(#H.actions==1 and H.actions[1][2]==102,'first-run save uploads once')
 check(after.firstRunWishlist and after.firstRunWishlist.key=='201172:2','first-run plan holds the edit')
 check(after.loadoutWishlists[2]==nil,'and no association is created under the empty slot')
end

-- 5. Writer level: a caller that skips the editor cannot assign an empty Saved Build.
reopen({echoes={}})
do
 local A=Nexus.GameAdapter
 local before=snapshot()
 local rolled={{spellId=201172,quality=0,stacks=1,locked=false}}
 local ok,reason=A.UpdateWishlistAssociationAfterSave(2,102,NAME,rolled,{})
 check(ok==false and reason=='that loadout slot is empty or unavailable','association writer refuses the empty slot: '..tostring(reason))
 check(T.Equal(before,snapshot()),'and writes nothing')
 -- the same refusal with a binding, as an open editor passes it
 local binding={actions=false,assignment=nil,firstRun=nil}
 ok=A.UpdateWishlistAssociationAfterSave(2,102,NAME,rolled,{},binding)
 check(ok==false and T.Equal(before,snapshot()),'refused with a binding too')
 -- sibling writers and the upload keep refusing empty content / slots
 check(A.SetLoadoutWishlistIdentity(2,NAME,rolled,{})==false,'SetLoadoutWishlistIdentity refuses the empty slot')
 check(A.UpdateWishlistAssociationAfterSave(1,102,NAME,{},{})==false,'empty content is refused')
 check(A.UpdateWishlistAssociationAfterSave(1,102,NAME,{},{[200767]=true})==false,'locked-only content with no rolled copy is refused')
 check(A.SetFirstLoadoutWishlistIdentity(NAME,{},{})==false,'first-run writer refuses empty content')
 check(A.UploadWishlist(102,NAME,{})==false,'upload refuses empty content')
 check(T.Equal(before,snapshot()),'no refusal wrote anything')
 -- supported Unassign of an existing association is untouched
 local populated={name='P',echoes={{spellId=200767,quality=0,stacks=1,locked=false}}}
 reopen(populated)
 A=Nexus.GameAdapter
 check(A.UpdateWishlistAssociationAfterSave(2,102,NAME,rolled,{})==true,'populated slot accepts the association')
 check(snapshot().loadoutWishlists[2]~=nil,'it is stored')
 A.ClearLoadoutWishlist(2)
 check(snapshot().loadoutWishlists[2]==nil,'Unassign still clears it')
end

-- 6. A NEW Wishlist whose editor was bound to the empty Saved Build (Show on an empty
-- active slot). It used to upload and then fail to assign; now nothing is uploaded.
reopen({echoes={}})
do
 local before=snapshot()
 Nexus.WishlistEditor.Show()
 catalog(201172):Click()
 _G.NexusWishlistNameInput:SetText('W15-NEW')
 button('Create Wishlist'):Click()
 check(H.popup==nil,'no confirmation for a new Wishlist bound to an empty Saved Build')
 check(#H.actions==0,'nothing is uploaded for it')
 check(T.Equal(before,snapshot()),'and nothing is assigned or cleared')
 check(said('Saved Build 2 is empty'),'the refusal says which Saved Build is empty')
end

-- 7. The delayed-retry path (upload spacing) re-checks the destination too.
reopen({echoes={{spellId=200767,quality=0,stacks=1,locked=false}}})
do
 local rolled={{spellId=201172,quality=0,stacks=1,locked=false}}
 check(KnownSlotUpload(Nexus.GameAdapter.UploadWishlist,103,'W15-SPACER',rolled)==true,'fixture: a recent upload starts the spacing window')
 local before=snapshot()
 editViaPicker()
 button('Save Wishlist'):Click();H.AcceptPopup()
 check(Nexus.WishlistEditor.IsApplyPending()==true,'precondition: the save waits for the upload spacing')
 H.perks.serverBuildSlots[2].echoes={}
 Nexus.WishlistEditor._PumpApplyRetry()
 check(Nexus.WishlistEditor.IsApplyPending()==false,'the retry is dropped, not repeated, when the destination emptied')
 check(#H.actions==1,'only the fixture upload was ever sent')
 check(T.Equal(before,snapshot()),'and no assignment changed')
end

-- 8. Controller level: the returned reasons, and an adapter that cannot tell.
reopen({echoes={}})
do
 local A=Nexus.GameAdapter
 local uploads=0
 local function controller(populatedCheck)
  local adapter={};for k,v in pairs(A) do adapter[k]=v end
  adapter.UploadWishlist=function(...) uploads=uploads+1;return A.UploadWishlist(...) end
  if populatedCheck==false then adapter.IsLoadoutPopulated=nil end
  local c=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=Nexus.Store,
   accountRoot=function() return {} end,notify=function() end})
  c.Initialize(adapter)
  return c
 end
 local rolled={{spellId=201172,quality=0,stacks=1,locked=false}}
 local before=snapshot()
 local c=controller()
 check(c.SelectLoadout(2)==true,'a new Wishlist is bound to Saved Build 2')
 check(c.LoadPendingEchoes(rolled),'with content')
 local data,why=c.PrepareApply('W15-CTRL')
 check(data==nil and why=='destination_empty','PrepareApply refuses with its own reason: '..tostring(why))
 local ok,reason=c.AcceptApply(2,'W15-CTRL',rolled)
 check(ok==false and reason=='destination_empty','the direct payload path is refused too and reports failure: '..tostring(ok)..'/'..tostring(reason))
 check(uploads==0 and T.Equal(before,snapshot()),'no upload and no change')
 -- An adapter that cannot say whether the Saved Build is populated is not treated as empty;
 -- the real writer still refuses the assignment, so nothing is assigned.
 local c2=controller(false)
 check(c2.SelectLoadout(2)==true and c2.LoadPendingEchoes(rolled),'second controller, same destination')
 local ok2,reason2=c2.AcceptApply(2,'W15-CTRL',rolled)
 check(reason2~='destination_empty','without the population check the controller does not refuse: '..tostring(reason2))
 check(uploads==1,'so the upload is attempted')
 check(snapshot().loadoutWishlists[2]==nil,'and the writer still stores no association under the empty slot')
end

print=rawPrint
print('PASS empty_saved_build_save: '..checks..' checks (picker gear, race after confirmation, populated and locked-only builds, first-run route, writers, new Wishlist, retry, controller)')
