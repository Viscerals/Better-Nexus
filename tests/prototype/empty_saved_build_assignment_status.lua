-- W6: an EMPTY positive active Saved Build with no association of its own, and a
-- retained first-run plan. The projection used to take the first-run plan as the
-- slot's saved assignment: the HUD said "Assigned Wishlist is unavailable" and the
-- projection carried the first-run plan's name. The first-run plan is not that
-- slot's assignment, so the slot is unassigned. Read-side only: no read writes,
-- promotes, clears or redirects anything.
-- Synthetic service mirrors only; no real account or game access.
local T=dofile('tests/prototype/startup_support.lua')
local NAME='W6-PLAN'
local checks=0
local function check(ok,msg) checks=checks+1; assert(ok,msg) end
local function boot(saved,slots,active)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil
 local h=dofile('tests/prototype/harness.lua')
 h.playerLevel=1
 wipe(h.db)
 h.AddEcho(201172,'Arcane Bombardment',0,5)
 h.AddEcho(200767,'Arcane Bond',0,5)
 h.perks.serverActiveSlot=active
 h.perks.serverBuildSlots=slots
 NexusDB=saved
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
  GetCharges=function()return 0 end,IsOfferPending=function()return false end,
  RequestCharges=function()end,
  ConfirmSpend=function()error('must not spend')end}
 h.Boot()
 return h
end
local H=boot(nil,{},0)
local function button(text)
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end
 end
 error('visible button absent: '..text)
end
local function catalog(id)
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==id then return f end
 end
 error('visible catalog row absent: '..id)
end
local function journal()
 if not ProjectEbonholdEchoJournal then CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)end
 ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
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
local PLAN_ECHO={spellId=200767,quality=0,stacks=1,locked=false}
local NOTE='Loadout 2 has no wishlist association. Set it in the Echo Journal.'

-- Boot a fresh character that kept `saved`, with Saved Build 2 as given and active.
local function reopen(slot2,active,mutate)
 local slots=H.Clone(mirror)
 if slot2~=nil then slots[2]=slot2 end
 local data=H.Clone(saved)
 if mutate then mutate(data) end
 H=boot(data,slots,active or 2)
 return H
end
local function emptyRow() return {name='',verified=false,echoes={}} end
local function populatedRow() return {name='Two',verified=false,echoes={H.Clone(PLAN_ECHO)}} end
local function lockedOnlyRow() return {name='Two',verified=false,echoes={{spellId=200767,quality=0,stacks=1,locked=true}}} end
local function firstRunRecord() return Nexus.Store.State().firstRunWishlist end

-- Visible text of the main panel's Setup screen.
local function shown(frame)
 local out={}
 for _,r in ipairs({frame:GetRegions()})do
  if r.GetText and r:IsVisible() then
   local t=r:GetText()
   if type(t)=='string' and t~='' then out[#out+1]=t end
  end
 end
 return out
end
local function has(texts,wanted)
 for _,t in ipairs(texts)do if t==wanted then return true end end
 return false
end
local function contains(texts,fragment)
 for _,t in ipairs(texts)do if t:find(fragment,1,true) then return true end end
 return false
end

-- Instrument slot reads and Store mutation entries of the CURRENT boot.
local function instrument()
 local c={slotReads=0,writes=0}
 local S=H.service
 local raw=S.GetServerBuildSlots
 S.GetServerBuildSlots=function(...) c.slotReads=c.slotReads+1;return raw(...) end
 local owner=Nexus.MainInternals.StoreAuthorityOwner
 local rawUpdate=owner.UpdateStateV1
 owner.UpdateStateV1=function(...) c.writes=c.writes+1;return rawUpdate(...) end
 return c
end
local function snapshot() return H.Clone(Nexus.Store.State()) end

-- 1. The defect: empty slot 2, no association for it, retained first-run plan.
reopen(emptyRow(),2)
do
 local A=Nexus.GameAdapter
 local c=instrument()
 local before=snapshot()
 check(before.firstRunWishlist and before.firstRunWishlist.key=='201172:1' and before.firstRunWishlist.name==NAME,
  'precondition: a first-run plan is retained')
 check(before.loadoutWishlists[2]==nil,'precondition: slot 2 has no association')
 check(A.IsLoadoutPopulated(2)==false and A.Slots().activeSlot==2,'precondition: the active slot is a known empty Saved Build')
 c.slotReads=0
 local a=A.AssignedWishlist()
 check(c.slotReads<=1,'one server slot read for the assignment read: '..c.slotReads)
 check(a.state=='unassigned','the empty slot is unassigned, not "'..tostring(a.state)..'"')
 check(a.name==nil,'the first-run plan name is not the empty slot\'s name: '..tostring(a.name))
 check(a.activeSlot==2 and a.wishlist==nil and a.entries==nil and a.key==nil and a.identity==nil,
  'no plan, rows, key or identity are projected for the empty slot')
 check(a.note==NOTE,'note: '..tostring(a.note))
 check(a.mirrorNote==nil,'no mirror note')
 local twice=A.AssignedWishlist()
 check(twice.state=='unassigned' and twice.name==nil and twice.note==NOTE,'a second read agrees')
 -- the consumers
 Nexus.Panel.Refresh()
 Nexus.Panel.Show()
 local model=Nexus.Panel._lastModel and Nexus.Panel._lastModel.assignment
 check(model and model.state=='unassigned' and model.name==nil and model.note==NOTE,
  'the HUD model carries the unassigned state: '..tostring(model and model.state))
 local texts=shown(NexusPanel)
 check(not contains(texts,'Assigned Wishlist is unavailable'),'the HUD does not say the Assigned Wishlist is unavailable')
 check(not contains(texts,NAME),'the HUD does not show the first-run plan as this slot\'s Wishlist')
 check(has(texts,'Assign a wishlist to this loadout'),'the HUD invites an assignment for this loadout')
 Nexus.OrbPanel.Show()
 check(NexusOrbPanel.plan:GetText()~=NAME and not NexusOrbPanel.start:IsEnabled(),
  'Orb mode shows no target and cannot start: '..tostring(NexusOrbPanel.plan:GetText()))
 local orb=A.AssignedWishlist()
 check(orb.state~='ready','Orb mode cannot treat the empty slot as ready')
 -- no read-side mutation and no host call
 check(c.writes==0,'no read entered a Store mutation: '..c.writes)
 check(T.Equal(before,snapshot()),'the first-run plan, assignments and every other field are untouched')
 check(firstRunRecord() and firstRunRecord().name==NAME,'the first-run plan is still retained')
 check(Nexus.Store.State().loadoutWishlists[2]==nil,'nothing was assigned to the empty slot')
 check(#H.actions==0,'no host action or upload')
 -- the HUD preparation makes one assignment read
 local hudReads,hudSlotReads,hudWrites=0,0,0
 local rawAssigned=A.AssignedWishlist
 A.AssignedWishlist=function(...)
  hudReads=hudReads+1
  local s0,w0=c.slotReads,c.writes
  local r=rawAssigned(...)
  hudSlotReads,hudWrites=hudSlotReads+c.slotReads-s0,hudWrites+c.writes-w0
  return r
 end
 check(Nexus.RefreshHudView()~=false,'the HUD refreshes')
 A.AssignedWishlist=rawAssigned
 check(hudReads==1 and hudSlotReads<=1 and hudWrites==0,
  'one HUD preparation: one assignment read, one slot read, no write: '..hudReads..' '..hudSlotReads..' '..hudWrites)
 -- the Saved Build then gets Echoes: the existing handoff, unchanged
 H.perks.serverBuildSlots[2]=populatedRow()
 local filled=A.AssignedWishlist()
 check(filled.state=='ready' and filled.name==NAME,'once the Saved Build is populated the first-run plan hands off: '..tostring(filled.state))
 check(Nexus.Store.State().loadoutWishlists[2] and Nexus.Store.State().loadoutWishlists[2].key=='201172:1'
  and firstRunRecord()==nil,'the handoff writes slot 2 and clears the first-run plan, as before')
end

-- 1b. The server's own shape for an emptied Saved Build is a verified row with no Echoes.
reopen({name='',verified=true,echoes={}},2)
do
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(Nexus.GameAdapter.Slots().bySlot[2].suspectParse==true,'precondition: the verified empty row')
 check(a.state=='unassigned' and a.name==nil and a.note==NOTE,'verified empty Saved Build: unassigned: '..tostring(a.state)..' '..tostring(a.name))
 check(firstRunRecord() and firstRunRecord().name==NAME,'the first-run plan is retained')
end

-- 2. Explicit Unassign: the empty slot is unassigned too, and stays so.
reopen(emptyRow(),2,function(d)
 for _,row in pairs(d.chars or {}) do if type(row)=='table' then row.firstRunWishlist=false end end
 if d.firstRunWishlist~=nil then d.firstRunWishlist=false end
end)
do
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(firstRunRecord()==false,'precondition: explicit Unassign marker')
 check(a.state=='unassigned' and a.name==nil,'explicit Unassign on an empty slot: '..tostring(a.state))
end

-- 3. Negative controls: the first-run plan and genuinely unavailable assignments keep their behavior.
-- 3a. No Saved Build selected (slot 0): the first-run plan is the target.
reopen(nil,0)
do
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(a.state=='ready' and a.name==NAME and a.note=='First-run wishlist target' and a.activeSlot==0,
  'slot 0: first-run target kept: '..tostring(a.state)..' '..tostring(a.note))
end
-- 3b. Slot 0 with a first-run plan whose data cannot be read: genuinely unavailable.
reopen(nil,0,function(d)
 local rec=d.firstRunWishlist
 local function broke(r) if type(r)=='table' then r.echoes=nil;r.key='999999:1' end end
 broke(rec)
 for _,row in pairs(d.chars or {}) do if type(row)=='table' then broke(row.firstRunWishlist) end end
end)
do
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(a.state=='unavailable' and a.name==NAME,'slot 0, unreadable first-run plan: still unavailable, named: '..tostring(a.state))
 Nexus.Panel.Refresh();Nexus.Panel.Show()
 check(contains(shown(NexusPanel),'Assigned Wishlist is unavailable'),'and the HUD still says so')
end
-- 3c. An active slot beyond the declared maximum is not a Saved Build: first-run route.
reopen(nil,9)
do
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(a.state=='ready' and a.name==NAME,'active slot beyond the declared maximum: first-run target kept: '..tostring(a.state))
end
-- 3c'. The same, with the server reporting an empty row for that number and an unreadable first-run plan.
reopen(nil,9,function(d)
 local function broke(r) if type(r)=='table' then r.echoes=nil;r.key='999999:1' end end
 broke(d.firstRunWishlist)
 for _,row in pairs(d.chars or {}) do if type(row)=='table' then broke(row.firstRunWishlist) end end
end)
do
 H.perks.serverBuildSlots[9]=emptyRow()
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(a.state=='unavailable' and a.name==NAME and a.activeSlot==9,
  'beyond the declared maximum, an empty row is not a Saved Build: first-run route, unavailable: '..tostring(a.state))
end
-- 3d. Populated active slot without association: the first-run plan hands off.
reopen(populatedRow(),2)
do
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(a.state=='ready' and a.name==NAME,'populated slot: handoff: '..tostring(a.state))
 check(Nexus.Store.State().loadoutWishlists[2] and firstRunRecord()==nil,'populated slot: slot written, first-run plan cleared')
end
-- 3e. Locked-only Saved Build counts as populated: same handoff.
reopen(lockedOnlyRow(),2)
do
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(a.state=='ready' and a.name==NAME,'locked-only slot: handoff: '..tostring(a.state))
end
-- 3f. A stored association that belongs to the empty slot itself is that slot's own assignment:
-- it stays unavailable under its own name (a different state from "no association").
reopen(emptyRow(),2,function(d)
 local function add(s)
  if type(s)=='table' and type(s.loadoutWishlists)=='table' then
   s.loadoutWishlists[2]={name='Own plan',key='999999:1',assignmentId='assigned:77'}
  end
 end
 add(d)
 for _,row in pairs(d.chars or {}) do add(row) end
end)
do
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(Nexus.Store.State().loadoutWishlists[2] and Nexus.Store.State().loadoutWishlists[2].name=='Own plan','precondition: slot 2 has its own association')
 check(a.state=='unavailable' and a.name=='Own plan','the slot\'s own association is still reported, under its own name: '..tostring(a.state)..' '..tostring(a.name))
end
-- 3g. Slot data for the active slot is missing (not known to be empty): unchanged.
reopen(nil,2)
do
 H.perks.serverBuildSlots[2]=nil
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(a.state=='unavailable' and a.name==NAME,'no slot row: not known empty, behavior unchanged: '..tostring(a.state))
end
-- 3h. Malformed slot echoes are not a known empty slot: unchanged.
reopen({name='',verified=false},2)
do
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(a.state=='unavailable' and a.name==NAME,'slot without an echo list: not known empty, unchanged: '..tostring(a.state))
end
-- 3i. Active slot not yet known: restoring, unchanged.
reopen(emptyRow(),nil)
do
 H.perks.serverActiveSlot=nil
 local a=Nexus.GameAdapter.AssignedWishlist()
 check(a.state=='restoring','unknown active slot with a saved first-run plan: '..tostring(a.state))
end

print('PASS empty_saved_build_assignment_status: '..checks..' checks (empty slot with a first-run plan is unassigned in the projection, HUD and Orb text; no read mutation; first-run, handoff, unavailable and unknown-data controls)')
