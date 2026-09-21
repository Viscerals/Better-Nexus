-- Independent review probe: actual clean Create -> select same row -> Unassign.
-- Real product handlers; retained synthetic harness and services only.
local H=dofile('tests/prototype/harness.lua')
H.playerLevel=1;wipe(H.db)
H.AddEcho(201172,'Arcane Bombardment',0,5)
H.perks.serverActiveSlot=0;H.perks.serverBuildSlots={}
ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
 GetCharges=function()return 0 end,IsOfferPending=function()return false end,
 RequestCharges=function()end,ConfirmSpend=function()error('review cannot spend')end}
H.Boot()
local function button(text)
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end
 end
 error('SETUP: missing visible button '..text)
end
local function journal()
 if not ProjectEbonholdEchoJournal then CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)end
 ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
end
journal();button('New Wishlist'):Click()
local row
for _,f in ipairs(H.frames)do
 if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==201172 then row=f;break end
end
assert(row,'SETUP: actual catalog row missing');row:Click()
local name='NEXUS-TEST-REVIEW-RESELECT-UNASSIGN'
NexusWishlistNameInput:SetText(name);button('Create Wishlist'):Click()
assert(H.popup and H.popup.which=='WISHLISTREALIZER_CREATE_WISHLIST','SETUP: create confirmation missing');H.AcceptPopup()
assert(#H.actions==1 and H.actions[1][1]=='upload','SETUP: expected one create upload')
H.perks.serverBuildSlots={[102]={name=name,verified=false,echoes=H.Clone(H.actions[1][4])}}
H.Notify();Nexus.GameAdapter.Poll();H.Advance(4);NexusEditorFrame:Hide()
assert(Nexus.GameAdapter.AssignedWishlist().state=='ready','SETUP: clean creation not ready')
local initial=Nexus.Store.State()
assert(initial.firstRunWishlist.assignmentId==initial.loadoutWishlists[1].assignmentId,'SETUP: initial handoff mismatch')
print('INITIAL',initial.firstRunWishlist.assignmentId,initial.loadoutWishlists[1].assignmentId)
journal();NexusActiveWishlistSelector:Click()
local selected
for _,r in ipairs(NexusWishlistOnlyPicker.children)do
 if r.nameButton and r.nameButton:IsVisible() and r.nameButton.text:GetText():find(name,1,true)then selected=r;break end
end
assert(selected,'SETUP: created source missing from actual picker');selected.nameButton:Click()
assert(Nexus.GameAdapter.AssignedWishlist().state=='ready','SETUP: selector assignment did not resolve')
local before=Nexus.Store.State()
print('RESELECTED',before.firstRunWishlist.assignmentId,before.loadoutWishlists[1].assignmentId)
journal();NexusActiveWishlistSelector:Click()
assert(NexusWishlistOnlyPicker.clearRow:IsVisible(),'SETUP: actual Unassign row hidden')
NexusWishlistOnlyPicker.clearRow:Click()
local after=Nexus.Store.State()
print('CLEARED',Nexus.GameAdapter.AssignedWishlist().state,tostring(after.firstRunWishlist),after.loadoutWishlists[1] and after.loadoutWishlists[1].assignmentId)
assert(Nexus.GameAdapter.AssignedWishlist().state=='unassigned','first-run Unassign must resolve immediately')
assert(#H.actions==1,'reselect and Unassign must not mutate services')
H.perks.serverBuildSlots[1]={name='First saved build',verified=true,echoes=H.Clone(H.perks.serverBuildSlots[102].echoes)}
H.perks.serverActiveSlot=1;H.Notify();Nexus.GameAdapter.Poll();H.Advance(1)
local later=Nexus.GameAdapter.AssignedWishlist()
print('NUMBERED_TRANSITION',later.state,later.name,later.identity)
assert(later.state=='unassigned','explicit Unassign must not revive this source after a same-source picker selection and first Saved Build transition')
assert(#H.actions==1,'numbered observation must not mutate services')
print('PASS same-source picker selection, actual Unassign and numbered transition')
