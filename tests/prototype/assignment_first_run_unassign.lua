-- Clean first-run creation followed by the actual Journal Unassign handler.
-- Synthetic services only; no native account or saved-data access.
local T=dofile('tests/prototype/startup_support.lua')
local NAME='NEXUS-TEST-UNASSIGN-91D850F'
local function boot(saved,slots,active)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil
 local h=dofile('tests/prototype/harness.lua')
 h.playerLevel=1;wipe(h.db)
 h.AddEcho(201172,'Arcane Bombardment',0,5)
 h.AddEcho(200767,'Arcane Bond',0,5)
 h.perks.serverActiveSlot=active or 0
 if active==false then h.perks.serverActiveSlot=nil end
 h.perks.serverBuildSlots=slots or {}
 if slots==false then h.perks.serverBuildSlots=nil end
 NexusDB=saved
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
  GetCharges=function()return 0 end,IsOfferPending=function()return false end,
  RequestCharges=function()end,ConfirmSpend=function()error('Unassign cannot spend')end}
 h.Boot();return h
end
local H=boot()
local function button(text)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end end
 error('visible button absent: '..text)
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
assert(row,'actual catalog row');row:Click()
local empty
for _,f in ipairs(H.frames)do if f:IsVisible() and f.slotState=='empty' then empty=f;break end end
assert(empty,'actual permanent-slot picker');empty:Click()
for _,f in ipairs(H.frames)do
 if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==200767 then row=f;break end
end
assert(row.data.spellId==200767,'actual permanent-target catalog row');row:Click()
NexusWishlistNameInput:SetText(NAME);button('Create Wishlist'):Click()
assert(H.popup and H.popup.which=='WISHLISTREALIZER_CREATE_WISHLIST');H.AcceptPopup()
assert(#H.actions==1 and H.actions[1][1]=='upload','actual create submits one source')
H.perks.serverBuildSlots={[102]={name=NAME,verified=false,echoes=H.Clone(H.actions[1][4])}}
H.Notify();Nexus.GameAdapter.Poll();H.Advance(4);NexusEditorFrame:Hide()
assert(Nexus.GameAdapter.AssignedWishlist().state=='ready','clean first-run creation resolves')
local created=H.Clone(NexusDB);local slots=H.Clone(H.perks.serverBuildSlots)
local original=Nexus.Store.State()
assert(original.firstRunWishlist.assignmentId==original.loadoutWishlists[1].assignmentId,'normal creation writes the same assignment handoff')
local function unassign()
 journal();NexusActiveWishlistSelector:Click()
 assert(NexusWishlistOnlyPicker.clearRow:IsVisible(),'actual Unassign row visible')
 NexusWishlistOnlyPicker.clearRow:Click()
end
local function unassigned(where)
 local a=Nexus.GameAdapter.AssignedWishlist()
 assert(a.state=='unassigned',where..': explicit first-run Unassign must be unassigned, not '..tostring(a.state))
 Nexus.Panel.Refresh();Nexus.OrbPanel.Show()
 assert(Nexus.Panel._lastModel.assignment.state=='unassigned',where..': main assignment agrees')
 assert(Nexus.OrbRuntime.Status().assignment.state=='unassigned' and not NexusOrbPanel.start:IsEnabled(),where..': Orb view cannot start')
 local s=Nexus.OrbRuntime.Status()
 assert(not s.running and not s.pending and s.spent==0 and s.reserved==0,where..': no Orb activity or exposure')
end
local function observe(rows,active)
 H.perks.serverBuildSlots=H.Clone(rows);H.perks.serverActiveSlot=active
 H.Notify();Nexus.GameAdapter.Poll();H.Advance(1)
end
unassign()
local state=Nexus.Store.State();local a=Nexus.GameAdapter.AssignedWishlist()
print('UNASSIGN_ACTUAL','state',a.state,'first',state.firstRunWishlist and state.firstRunWishlist.key,
 'slot1',state.loadoutWishlists[1] and state.loadoutWishlists[1].key,'note',a.note)
assert(a.state=='unassigned','explicit first-run Unassign must be unassigned, not '..tostring(a.state))
assert(not state.firstRunWishlist and state.loadoutWishlists[1]==nil,'explicit Unassign removes only its own first-Saved-Build handoff')
assert(#H.actions==1,'Unassign submits no upload or gameplay action')
assert(T.Equal(slots,H.perks.serverBuildSlots),'Unassign preserves the server Wishlist')
assert(T.Equal(original.lockDesignTargetsBySlot,state.lockDesignTargetsBySlot),'Unassign keeps the exact permanent-target design')
unassigned('after click')
local cleared=H.Clone(NexusDB)
H=boot(H.Clone(cleared),H.Clone(slots));unassigned('reloaded')
assert(not Nexus.Store.State().firstRunWishlist,'explicit unassignment persists')
observe({},0);unassigned('empty mirror')
observe(slots,0);unassigned('late old mirror')
local candidates=Nexus.GameAdapter.GetWishlistCandidates();local retained
for _,c in ipairs(candidates)do if c.slot==102 then retained=c end end
assert(retained and retained.name==NAME and retained.key=='201172:1','exact server source remains available without assignment')
local promoted=H.Clone(slots)
promoted[1]={name='Owned first Saved Build',verified=true,echoes=H.Clone(slots[102].echoes)}
observe(promoted,1);unassigned('first Saved Build appears')
assert(Nexus.Store.State().loadoutWishlists[1]==nil,'no removed handoff can reactivate')
observe(slots,0);unassigned('back to first-run')
assert(#H.actions==0,'reload and reordered observations submit nothing')
H=boot(H.Clone(cleared),false,false)
assert(Nexus.GameAdapter.AssignedWishlist().state~='ready','unknown mirrors cannot assign a source')
observe(slots,0);unassigned('unknown source resolves')
assert(#H.actions==0,'late restoration makes no mutation')
-- Actual picker selection replaces the deliberate-unassigned state.
journal();NexusActiveWishlistSelector:Click()
local chosen
for _,r in ipairs(NexusWishlistOnlyPicker.children)do
 if r.nameButton and r.nameButton.text:GetText():find(NAME,1,true)then chosen=r;break end
end
assert(chosen,'retained source appears in actual picker');chosen.nameButton:Click()
local selected=Nexus.GameAdapter.AssignedWishlist()
assert(selected.state=='ready' and selected.name==NAME,'deliberate selection assigns the exact retained source')
assert(type(Nexus.Store.State().firstRunWishlist)=='table','selection installs the chosen assignment')
assert(#H.actions==0,'local reassignment does not upload or mutate gameplay')
print('PASS actual first-run create, Unassign, delayed mirrors, reload, preserved source/design and explicit reassignment')

-- An unrelated saved assignment must survive and must not look like restoration.
H=boot(H.Clone(created),H.Clone(slots))
assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)
 s.loadoutWishlists[2]=H.Clone(s.firstRunWishlist)
 s.loadoutWishlists[2].assignmentId='assigned:unrelated'
 s.loadoutWishlists[2].name='Unrelated saved plan'
end))
local unrelated=H.Clone(Nexus.Store.State().loadoutWishlists[2])
unassign()
local a=Nexus.GameAdapter.AssignedWishlist()
print('UNASSIGN_WITH_UNRELATED','state',a.state)
assert(a.state=='unassigned','explicit first-run Unassign with unrelated assignments must be unassigned, not '..tostring(a.state))
assert(T.Equal(unrelated,Nexus.Store.State().loadoutWishlists[2]),'unrelated assignment remains exact')
unassigned('unrelated slot 2')
local otherCleared=H.Clone(NexusDB)
H=boot(otherCleared,H.Clone(slots));unassigned('unrelated slot 2 reload')
local numbered=H.Clone(slots)
numbered[2]={name='Owned saved build 2',verified=true,echoes=H.Clone(slots[102].echoes)}
observe(numbered,2)
assert(Nexus.GameAdapter.AssignedWishlist().name==unrelated.name,'numbered assignment still resolves when selected')
observe(numbered,nil)
assert(Nexus.GameAdapter.AssignedWishlist().state=='restoring','unknown active identity still waits for existing numbered assignments')
observe(numbered,0);unassigned('known zero after unknown identity')
assert(#H.actions==0,'Unassign and observations cause no service mutation')
print('PASS actual first-run Unassign with unrelated assignment preserved')

-- Equal names/content and absent identity must not delete an unrelated slot-1 record.
for _,mode in ipairs({'other-identity','legacy-no-identity'})do
 H=boot(H.Clone(created),H.Clone(slots))
 assert(Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(s)
  if mode=='other-identity' then s.loadoutWishlists[1].assignmentId='assigned:other'
  else s.firstRunWishlist.assignmentId=nil;s.loadoutWishlists[1].assignmentId=nil end
 end))
 local keep=H.Clone(Nexus.Store.State().loadoutWishlists[1])
 unassign();unassigned(mode)
 assert(T.Equal(keep,Nexus.Store.State().loadoutWishlists[1]),'only proven matching handoff may be removed')
 H=boot(H.Clone(NexusDB),H.Clone(slots));unassigned(mode..' reload')
 assert(T.Equal(keep,Nexus.Store.State().loadoutWishlists[1]),'unknown or unrelated slot-1 record persists unchanged')
 assert(#H.actions==0,'legacy and unrelated handling cannot mutate services')
end
-- Existing damaged state is not migrated or silently recovered on installation.
local damaged=H.Clone(created)
for _,s in pairs(damaged.chars)do
 s.loadoutWishlists[0]=H.Clone(s.firstRunWishlist);s.firstRunWishlist=nil
end
H=boot(damaged,H.Clone(slots))
local broken=H.Clone(Nexus.Store.State())
assert(Nexus.GameAdapter.AssignedWishlist().state=='restoring','unmarked damaged state still requires deliberate recovery')
observe({},0);observe(slots,0)
assert(Nexus.GameAdapter.AssignedWishlist().state=='restoring','passive mirrors do not repair damaged state')
assert(Nexus.Store.State().firstRunWishlist==nil and T.Equal(broken.loadoutWishlists,Nexus.Store.State().loadoutWishlists),'all damaged associations remain unchanged')
assert(#H.actions==0,'no automatic repair or gameplay mutation')
print('PASS exact handoff removal, unrelated/legacy preservation, normal loading distinction and no automatic damaged-state repair')
