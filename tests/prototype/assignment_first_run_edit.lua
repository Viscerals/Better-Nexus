-- NATIVE-03: actual first-run Journal create, reload, Edit, plus, Save and Close.
-- Synthetic service mirrors only; no real account or game access.
local T=dofile('tests/prototype/startup_support.lua')
local NAME='NEXUS-TEST-20260919-173-A'
local function boot(saved,slots)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil
 local h=dofile('tests/prototype/harness.lua')
 -- The retained harness has no XML templates. Supply only the standard
 -- UIPanelCloseButton template's parent-hide behavior, not a product handler.
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
 h.perks.serverActiveSlot=0
 h.perks.serverBuildSlots=slots or {}
 if slots==false then h.perks.serverBuildSlots=nil end
 NexusDB=saved
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
  GetCharges=function()return 0 end,IsOfferPending=function()return false end,
  RequestCharges=function()end,
  ConfirmSpend=function()error('first-run editing must not spend')end}
 h.Boot()
 return h
end
local H=boot()
local function button(text)
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end
 end
 error('visible button absent: '..text)
end
local function catalog(id)
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f:IsVisible() and f.status and f.data
   and f.data.spellId==id then return f end
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
local function closeEditor()
 for _,f in ipairs(NexusEditorFrame.children)do
  if f._testTemplateClose then f:Click();return end
 end
 error('actual editor Close control absent')
end
local function assertPlan(copies,where)
 local a=Nexus.OrbRuntime.Status().assignment
 print('NATIVE03',where,'state',a.state,'name',a.name,'key',a.key,'identity',a.identity,'active',a.activeSlot)
 assert(a.state=='ready' and a.name==NAME and a.activeSlot==0,
  'NATIVE-03: saved first-run assignment must resolve after edit, not remain '..tostring(a.state))
 local rolled,permanent=0,0
 for _,e in ipairs(a.entries)do
  if e.spellId==201172 and e.quality==0 and e.locked==false then rolled=rolled+e.stacks end
  if e.spellId==200767 and e.quality==0 and e.locked==true then permanent=permanent+e.stacks end
 end
 assert(rolled==copies and permanent==1,'saved first-run assignment preserves exact rolled copies and locked design')
 assert(NexusPanel:IsShown(),'main panel remains shown after the editor closes')
 Nexus.Panel.Refresh();Nexus.OrbPanel.Show()
 assert(Nexus.Panel._lastModel.progress.wishlistName==NAME,'main projection uses the edited first-run assignment')
 assert(NexusOrbPanel.snapshot.config.name==NAME,'Orb view agrees with main assignment')
 assert(NexusPanel.toLockText:GetText():find('Arcane Bond',1,true),'actual main locked-target text survives')
 local s=Nexus.OrbRuntime.Status()
 assert(not s.running and not s.pending and s.spent==0 and s.reserved==0,'editing keeps Orb mode idle with zero exposure')
 button('Close'):Click()
 return a
end
journal();button('New Wishlist'):Click()
catalog(201172):Click()
local empty
for _,f in ipairs(H.frames)do if f:IsVisible() and f.slotState=='empty' then empty=f;break end end
assert(empty,'actual empty locked-Echo slot picker');empty:Click();catalog(200767):Click()
local nameBox=assert(_G.NexusWishlistNameInput,'normal editor name input')
nameBox:SetText(NAME)
button('Create Wishlist'):Click()
assert(H.popup and H.popup.which=='WISHLISTREALIZER_CREATE_WISHLIST')
H.AcceptPopup()
assert(#H.actions==1 and H.actions[1][1]=='upload' and H.actions[1][2]==0,'one actual adapter create submission')
H.perks.serverBuildSlots={[102]={name=NAME,verified=false,echoes=H.Clone(H.actions[1][4])}}
H.Notify();Nexus.GameAdapter.Poll();H.Advance(4)
closeEditor();assertPlan(1,'created')
local saved=H.Clone(NexusDB);local slots=H.Clone(H.perks.serverBuildSlots)
local function observe(rows)
 H.perks.serverBuildSlots=H.Clone(rows)
 H.Notify();Nexus.GameAdapter.Poll();H.Advance(4)
end
for _,order in ipairs({'late','early','reordered'})do
 H=boot(H.Clone(saved),H.Clone(slots));local before=assertPlan(1,order..' reloaded')
 journal();assert(NexusAssociatedWishlistDesignButton:IsEnabled());NexusAssociatedWishlistDesignButton:Click()
 selected(201172).plus:Click()
 local submit=H.service.UploadServerBuildSlot
 if order=='early' then
  H.service.UploadServerBuildSlot=function(slot,name,entries)
   local ok=submit(slot,name,entries)
   H.perks.serverBuildSlots={[slot]={name=name,verified=false,echoes=H.Clone(entries)}}
   H.Notify();Nexus.GameAdapter.Poll()
   return ok
  end
 end
 button('Save Wishlist'):Click()
 assert(H.popup and H.popup.which=='WISHLISTREALIZER_UPDATE_WISHLIST')
 H.AcceptPopup()
 assert(#H.actions==1 and H.actions[1][1]=='upload' and H.actions[1][2]==102,'one exact existing source edit submission')
 assert(H.actions[1][4][1].stacks==2,'adapter submission contains the requested copy edit')
 local stored=Nexus.Store.State()
 print('NATIVE03_SAVED',order,'first',stored.firstRunWishlist and stored.firstRunWishlist.key,
  'slot0',stored.loadoutWishlists and stored.loadoutWishlists[0] and stored.loadoutWishlists[0].key,
  'slot1',stored.loadoutWishlists and stored.loadoutWishlists[1] and stored.loadoutWishlists[1].key)
 -- This assertion is the original native symptom, before the stronger storage checks.
 local edited=Nexus.OrbRuntime.Status().assignment
 assert(edited.state=='ready','NATIVE-03: saved first-run assignment must resolve after edit, not remain '..tostring(edited.state))
 assert(stored.firstRunWishlist.key=='201172:2' and stored.loadoutWishlists[0]==nil,'edit cannot create a slot-zero association or clear first-run')
 assert(stored.loadoutWishlists[1].key=='201172:2','first-Saved-Build handoff has the edited contents')
 assert(edited.identity~=before.identity and edited.identity==stored.firstRunWishlist.assignmentId,'edit creates one new durable assignment identity')
 local replacement={[102]={name=NAME,verified=false,echoes=H.Clone(H.actions[1][4])}}
 closeEditor();H.Advance(1);assertPlan(2,order..' before response')
 if order=='reordered' then
  observe({});assertPlan(2,'empty mirror')
  observe(slots);assertPlan(2,'stale mirror')
  local wrong=H.Clone(replacement);wrong[102].echoes[1].stacks=3
  wrong[101]={name=NAME,verified=false,echoes=H.Clone(slots[102].echoes)}
  observe(wrong);assertPlan(2,'same names with wrong contents')
 end
 observe(replacement);assertPlan(2,order..' edited')
 if order=='reordered' then
  observe(slots);assertPlan(2,'late stale response')
  observe(replacement);assertPlan(2,'final current response')
 end
 local final=H.Clone(Nexus.Store.State())
 for _,invalid in ipairs({0,-1,1.5,'invalid'})do
  assert(not Nexus.GameAdapter.UpdateWishlistAssociationAfterSave(invalid,102,NAME,H.actions[1][4],{}),'invalid loadout identifier is refused')
  assert(not Nexus.GameAdapter.UpdateWishlistAssociationAfterSave(1,invalid,NAME,H.actions[1][4],{}),'invalid server identifier is refused')
  assert(T.Equal(final,Nexus.Store.State()),'invalid association update changes no durable state')
 end
 assert(#H.actions==1,'notifications and presentation never repeat upload or mutate gameplay')
 local persisted=H.Clone(NexusDB)
 H=boot(persisted,false)
 assert(Nexus.OrbRuntime.Status().assignment.state=='restoring','reload with unknown source data reports restoration')
 observe(slots);assertPlan(2,order..' reload with stale mirror')
 observe(replacement);assertPlan(2,order..' reload complete')
 assert(#H.actions==0,'reload and delayed restoration make no mutation')
end
Nexus.Panel.Hide()
journal();NexusAssociatedWishlistDesignButton:Click();closeEditor();H.Advance(1)
assert(not NexusPanel:IsShown(),'editor Close preserves an explicitly hidden main panel')
assert(#H.actions==0,'inspection with the HUD hidden makes no mutation')
print('PASS NATIVE-03 first-run create/reload/edit; early, late, reordered mirrors; exact design, identity, invalid-slot refusal and zero gameplay actions')
