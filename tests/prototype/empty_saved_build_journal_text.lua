-- W6 presentation: a known-empty positive Saved Build with no association of its own
-- and a retained first-run plan. The Journal keeps the first-run plan beside the empty
-- Saved Build on purpose (its gear opens first-run editing without a destination), so
-- its labels, tooltips, the assignment note, the HUD hint and the Orb text must say that
-- the plan is not assigned to the Saved Build. Wording only: every action stays as it
-- was (picker selection and the row gear still target the numbered slot and are
-- refused, Unassign still clears the slot, the gear edits the first-run plan).
-- Synthetic service mirrors only; no real account or game access.
local T=dofile('tests/prototype/startup_support.lua')
local NAME='W6-TEXT-PLAN'
local checks=0
local function check(ok,msg) checks=checks+1; assert(ok,msg) end
local notices={}
print=function(...)
 local parts={}
 for i=1,select('#',...) do parts[#parts+1]=tostring((select(i,...))) end
 notices[#notices+1]=table.concat(parts,' ')
end
local function said(fragment)
 for _,line in ipairs(notices) do if line:find(fragment,1,true) then return true end end
 return false
end
local tip={}
local function boot(saved,slots,active)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;NexusWishlistOnlyPicker=nil
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
 h.perks.serverActiveSlot=active
 h.perks.serverBuildSlots=slots
 NexusDB=saved
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
  GetCharges=function()return 0 end,IsOfferPending=function()return false end,
  RequestCharges=function()end,
  ConfirmSpend=function()error('must not spend')end}
 h.Boot()
 function GameTooltip:SetOwner(owner) self.owner=owner;tip={} end
 function GameTooltip:ClearLines() tip={} end
 function GameTooltip:AddLine(text) tip[#tip+1]=tostring(text) end
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
local EMPTY_NOTE='Loadout 2 is empty. A Wishlist can be assigned once it holds Echoes.'
local OLD_NOTE='Loadout 2 has no wishlist association. Set it in the Echo Journal.'

local function broke(r) if type(r)=='table' then r.echoes=nil;r.key='999999:1' end end
local function eachRow(d,fn) fn(d);for _,row in pairs(d.chars or {}) do if type(row)=='table' then fn(row) end end end
local function reopen(slot2,active,mutate)
 local slots=H.Clone(mirror)
 if slot2~=nil then slots[2]=slot2 end
 local data=H.Clone(saved)
 if mutate then mutate(data) end
 notices={}
 H=boot(data,slots,active or 2)
 return H
end
local function emptyRow() return {name='',verified=false,echoes={}} end
local function populatedRow() return {name='Two',verified=false,echoes={H.Clone(PLAN_ECHO)}} end
local function snapshot() return H.Clone(Nexus.Store.State()) end
local function firstRun() return Nexus.Store.State().firstRunWishlist end

local function texts(frame)
 local out={}
 for _,r in ipairs({frame:GetRegions()})do
  if r.GetText and r:IsVisible() then
   local t=r:GetText()
   if type(t)=='string' and t~='' then out[#out+1]=t end
  end
 end
 return table.concat(out,'\n')
end
local function has(text,fragment) return text:find(fragment,1,true)~=nil end
local function Hover(frame)
 local enter=assert(frame:GetScript('OnEnter'),'control has a tooltip handler')
 enter(frame)
 local text=table.concat(tip,'\n')
 local leave=frame:GetScript('OnLeave');if leave then leave(frame) end
 return text
end
local function instrument()
 local c={slotReads=0,writes=0}
 local raw=H.service.GetServerBuildSlots
 H.service.GetServerBuildSlots=function(...) c.slotReads=c.slotReads+1;return raw(...) end
 local owner=Nexus.MainInternals.StoreAuthorityOwner
 local rawUpdate=owner.UpdateStateV1
 owner.UpdateStateV1=function(...) c.writes=c.writes+1;return rawUpdate(...) end
 return c
end
local function openPicker()
 journal()
 if NexusWishlistOnlyPicker and NexusWishlistOnlyPicker:IsShown() then NexusActiveWishlistSelector:Click() end
 NexusActiveWishlistSelector:Click()
 check(NexusWishlistOnlyPicker:IsShown(),'actual selector opens its picker')
 return NexusWishlistOnlyPicker
end
local function pickerRow(p)
 for _,r in ipairs(p.children)do
  if r.nameButton and r:IsVisible() and r.nameButton.text:GetText():find(NAME,1,true) then return r end
 end
 error('picker row missing: '..NAME)
end
-- Everything the Journal, the HUD and the Orb panel say, for one boot.
local function surfaces()
 local s={}
 journal()
 s.label=NexusActiveWishlistSelector:GetParent().label:GetText()
 s.selectorText=NexusActiveWishlistSelector.text:GetText()
 s.gearEnabled=NexusAssociatedWishlistDesignButton:IsEnabled()
 s.gearTip=Hover(NexusAssociatedWishlistDesignButton)
 s.selectorTip=Hover(NexusActiveWishlistSelector)
 local p=openPicker()
 local row=pickerRow(p)
 s.rowTip=Hover(row.nameButton)
 s.rowGearTip=Hover(row.gear)
 s.unassignTip=p.clearRow and p.clearRow:IsVisible() and Hover(p.clearRow) or nil
 NexusActiveWishlistSelector:Click()
 Nexus.Panel.Refresh();Nexus.Panel.Show()
 s.hud=texts(NexusPanel)
 Nexus.OrbPanel.Show();Nexus.OrbPanel.Refresh()
 s.orbPlan=NexusOrbPanel.plan:GetText();s.orbTargets=NexusOrbPanel.targets:GetText()
 return s
end

-- 1. The context: empty slot 2, no association of its own, a retained first-run plan.
reopen(emptyRow(),2)
do
 local A=Nexus.GameAdapter
 local c=instrument()
 local before=snapshot()
 check(firstRun() and firstRun().name==NAME and before.loadoutWishlists[2]==nil,'precondition: first-run plan retained, slot 2 has no association')
 local r=A.AssignedWishlist()
 check(r.state=='unassigned' and r.emptySlot==true and r.note==EMPTY_NOTE and r.name==nil,
  'the projection marks the empty slot and says what is possible: '..tostring(r.note))
 check(A.WishlistNote()==EMPTY_NOTE,'the adapter note is the same text')
 c.slotReads=0
 local s=surfaces()
 check(c.writes==0,'rendering every surface enters no Store mutation: '..c.writes)
 check(T.Equal(before,snapshot()),'rendering changes no record')
 -- the Journal keeps showing the first-run plan, on purpose
 check(has(s.label,'Empty Saved Build'),'label names the empty Saved Build: '..s.label)
 check(has(s.selectorText,NAME) and s.gearEnabled,'the first-run plan is still shown and still editable from the gear')
 -- gear tooltip
 check(has(s.gearTip,'Edit first-run Wishlist'),'gear tooltip names first-run editing')
 check(has(s.gearTip,'first-run Wishlist for editing') and has(s.gearTip,'nothing is assigned to it'),'gear tooltip says nothing is assigned')
 check(not has(s.gearTip,'Edit assigned Wishlist') and not has(s.gearTip,'assigned to this Saved Build'),'gear tooltip no longer calls it assigned')
 check(has(s.gearTip,'This does not activate another build.'),'gear tooltip keeps its activation sentence')
 -- selector tooltip
 check(has(s.selectorTip,'Automation Wishlist'),'selector tooltip title retained')
 check(has(s.selectorTip,'This Saved Build is empty, so no Wishlist can be assigned to it until it holds Echoes.')
  and has(s.selectorTip,'not an assignment to this Saved Build'),'selector tooltip says the shown name is not an assignment')
 check(not has(s.selectorTip,'Assigns a wishlist reference to the Saved Build currently selected'),'selector tooltip no longer promises an assignment')
 check(has(s.selectorTip,'With Auto ON, Nexus may replace the active Saved Build'),'selector tooltip keeps its Auto warning')
 -- picker row and Unassign tooltips
 check(has(s.rowTip,'Assign Wishlist') and has(s.rowTip,'Target: Empty Saved Build slot'),'row tooltip names the action and target')
 check(has(s.rowTip,'assigning a Wishlist to it is refused until it holds Echoes'),'row tooltip says the assignment is refused')
 check(not has(s.rowTip,'Sets this Wishlist as the target for this loadout'),'row tooltip no longer promises a target')
 check(s.rowGearTip=='Edit wishlist','row gear tooltip unchanged')
 check(s.unassignTip and has(s.unassignTip,'This Saved Build has no Wishlist of its own. This does not remove the first-run Wishlist.')
  and has(s.unassignTip,'Does not change or restore the Saved Build.'),'Unassign tooltip says it does not remove the first-run Wishlist')
 check(not has(s.unassignTip,'stops using it for this loadout'),'Unassign tooltip no longer says it stops using this Wishlist for the loadout')
 -- HUD and Orb
 check(has(s.hud,'Assign a wishlist to this loadout') and has(s.hud,EMPTY_NOTE),'HUD shows its title and the empty-slot hint')
 check(not has(s.hud,'Assign an existing wishlist to this loadout') and not has(s.hud,'Assigned Wishlist is unavailable'),
  'HUD no longer invites an assignment it would refuse')
 check(not has(s.hud,NAME),'HUD does not show the first-run plan')
 check(s.orbPlan=='Assigned Wishlist: none' and s.orbTargets==EMPTY_NOTE,'Orb panel: no target, and the same hint: '..tostring(s.orbTargets))
 check(not has(s.hud..s.orbTargets..s.rowTip..s.selectorTip..s.gearTip,'Set it in the Echo Journal'),'no surface sends the player to the Journal to assign')
 -- tooltips and refreshes make no host read of their own
 c.slotReads=0
 Hover(NexusAssociatedWishlistDesignButton);Hover(NexusActiveWishlistSelector)
 check(c.slotReads==0 and c.writes==0,'hovering the gear and selector reads no slots and writes nothing: '..c.slotReads)
 c.slotReads=0
 Nexus.JournalTab.RefreshAssociations()
 local emptyRefresh=c.slotReads
 -- 3 on 53424b6, before the wording change: the wording adds no read.
 check(emptyRefresh<=3,'a Journal refresh in the empty context makes no more slot reads than before: '..emptyRefresh)
 check(#H.actions==0,'no upload or host action')
end

-- 2. The actions are untouched: the same targets, the same refusals, the same records.
-- 2a. The picker row selects for the numbered slot, which is refused; nothing changes.
reopen(emptyRow(),2)
do
 local before=snapshot()
 local p=openPicker()
 pickerRow(p).nameButton:Click()
 check(said('empty or unavailable'),'picker selection is refused with the existing reason')
 check(T.Equal(before,snapshot()),'picker selection changes no record')
 check(#H.actions==0,'and starts no upload')
end
-- 2b. The row gear still opens the editor bound to the numbered slot; its save is refused (W15).
reopen(emptyRow(),2)
do
 local before=snapshot()
 local p=openPicker()
 pickerRow(p).gear:Click()
 selected(201172).plus:Click()
 button('Save Wishlist'):Click()
 check(H.popup==nil and #H.actions==0,'row-gear editor save to the empty slot is refused without a confirmation or upload')
 check(said('Saved Build 2 is empty'),'with the existing explanation')
 check(T.Equal(before,snapshot()),'and no record changes')
end
-- 2c. Unassign still targets the numbered slot, not the first-run plan.
reopen(emptyRow(),2)
do
 local A=Nexus.GameAdapter
 local cleared,clearedFirst={},0
 local rawClear,rawFirst=A.ClearLoadoutWishlist,A.ClearFirstRunWishlist
 A.ClearLoadoutWishlist=function(slot,...) cleared[#cleared+1]=slot;return rawClear(slot,...) end
 A.ClearFirstRunWishlist=function(...) clearedFirst=clearedFirst+1;return rawFirst(...) end
 local before=H.Clone(firstRun())
 local p=openPicker()
 check(p.clearRow and p.clearRow:IsVisible(),'the Unassign row is offered beside the first-run plan')
 p.clearRow:GetScript('OnClick')(p.clearRow)
 check(#cleared==1 and cleared[1]==2 and clearedFirst==0,'Unassign clears the numbered slot only')
 check(T.Equal(before,firstRun()),'the first-run plan is kept')
 check(Nexus.Store.State().loadoutWishlists[2]==nil,'and the empty slot still has no association')
end
-- 2d. The design gear edits the first-run plan with no numbered destination and saves it.
reopen(emptyRow(),2)
do
 journal()
 check(NexusAssociatedWishlistDesignButton:IsEnabled(),'the gear is enabled for the first-run plan')
 NexusAssociatedWishlistDesignButton:Click()
 selected(201172).plus:Click()
 button('Save Wishlist'):Click();H.AcceptPopup();H.Advance(4)
 local after=snapshot()
 check(#H.actions==1 and H.actions[1][2]==102,'first-run editing uploads once')
 check(after.firstRunWishlist and after.firstRunWishlist.key=='201172:2','the first-run plan holds the edit')
 check(after.loadoutWishlists[2]==nil,'no association is created under the empty slot')
 Nexus.Panel.Refresh()
 local m=Nexus.Panel._lastModel and Nexus.Panel._lastModel.assignment
 check(m and m.state=='unassigned' and m.emptySlot==true and m.note==EMPTY_NOTE,'and the HUD model still says the Saved Build is empty and unassigned')
end

-- 3. Controls: nothing outside the known-empty context changes its words.
-- 3a. Populated Saved Build (first-run plan handed off): the assigned wording stays.
reopen(populatedRow(),2)
do
 local s=surfaces()
 check(has(s.gearTip,'Edit assigned Wishlist') and has(s.gearTip,'Open the Wishlist assigned to this Saved Build.'),'populated: gear tooltip unchanged')
 check(has(s.selectorTip,'Assigns a wishlist reference to the Saved Build currently selected in the server dropdown.'),'populated: selector tooltip unchanged')
 check(has(s.rowTip,'Sets this Wishlist as the target for this loadout.') and not has(s.rowTip,'refused'),'populated: row tooltip unchanged')
 check(has(s.unassignTip,'Keeps the Wishlist; stops using it for this loadout.'),'populated: Unassign tooltip unchanged')
 check(not has(s.hud,EMPTY_NOTE) and has(s.hud,NAME),'populated: the HUD shows the handed-off plan')
 check(s.orbPlan=='Assigned Wishlist: '..NAME,'populated: Orb shows the assigned plan')
end
-- 3b. No Saved Build selected (slot 0): the first-run plan is the target; wording unchanged.
reopen(nil,0)
do
 local s=surfaces()
 check(has(s.gearTip,'Edit assigned Wishlist') and has(s.selectorTip,'Assigns a wishlist reference')
  and has(s.rowTip,'Sets this Wishlist as the target for this loadout.') and has(s.unassignTip,'Keeps the Wishlist'),'slot 0: Journal wording unchanged')
 check(s.orbPlan=='Assigned Wishlist: '..NAME,'slot 0: Orb shows the first-run target')
end
-- 3c. Populated Saved Build with no association and no first-run plan: the generic HUD guidance and old note stay.
reopen(populatedRow(),2,function(d) eachRow(d,function(r) r.firstRunWishlist=nil end) end)
do
 local r=Nexus.GameAdapter.AssignedWishlist()
 check(r.state=='unassigned' and r.emptySlot==nil and r.note==OLD_NOTE,'populated unassigned: old note, no empty-slot flag: '..tostring(r.note))
 Nexus.Panel.Refresh();Nexus.Panel.Show()
 local hud=texts(NexusPanel)
 check(has(hud,'Assign an existing wishlist to this loadout, or create a new one.') and not has(hud,OLD_NOTE),'populated unassigned: generic HUD guidance unchanged')
end
-- 3d. Populated Saved Build whose first-run plan cannot be read: genuinely unavailable.
reopen(populatedRow(),2,function(d) eachRow(d,function(r) broke(r.firstRunWishlist) end) end)
do
 local r=Nexus.GameAdapter.AssignedWishlist()
 check(r.state=='unavailable' and r.emptySlot==nil and r.note==nil,'populated, unreadable plan: unavailable, no empty-slot flag, note as before: '..tostring(r.state)..' '..tostring(r.note))
 Nexus.Panel.Refresh();Nexus.Panel.Show()
 check(has(texts(NexusPanel),'Assigned Wishlist is unavailable') and not has(texts(NexusPanel),EMPTY_NOTE),'and the HUD says so')
end
-- 3e. Slot 0 with an unreadable first-run plan: unavailable, unchanged.
reopen(nil,0,function(d) eachRow(d,function(r) broke(r.firstRunWishlist) end) end)
do
 local r=Nexus.GameAdapter.AssignedWishlist()
 check(r.state=='unavailable' and r.emptySlot==nil,'slot 0, unreadable plan: unavailable')
 Nexus.Panel.Refresh();Nexus.Panel.Show()
 check(has(texts(NexusPanel),'Assigned Wishlist is unavailable'),'and the HUD says so')
end
-- 3f. Unknown or malformed data for the active slot is not announced as empty by the HUD or Orb.
for _,case in ipairs({{tag='no slot row'},{tag='no echo list',row={name='',verified=false}}})do
 reopen(case.row,2)
 H.perks.serverBuildSlots[2]=case.row
 local r=Nexus.GameAdapter.AssignedWishlist()
 check(r.state=='unavailable' and r.emptySlot==nil and r.note==OLD_NOTE,case.tag..': unavailable, old note, no empty-slot flag: '..tostring(r.state)..' '..tostring(r.note))
 Nexus.Panel.Refresh();Nexus.Panel.Show()
 check(has(texts(NexusPanel),'Assigned Wishlist is unavailable') and not has(texts(NexusPanel),EMPTY_NOTE),case.tag..': HUD unchanged')
end
-- 3g. The empty slot's own stored association is a different state: unavailable under its own name.
reopen(emptyRow(),2,function(d)
 eachRow(d,function(r) if type(r.loadoutWishlists)=='table' then r.loadoutWishlists[2]={name='Own plan',key='999999:1',assignmentId='assigned:77'} end end)
end)
do
 local r=Nexus.GameAdapter.AssignedWishlist()
 check(r.state=='unavailable' and r.name=='Own plan' and r.emptySlot==nil,'own association on the empty slot: unavailable, its own name, no empty-slot flag')
 Nexus.Panel.Refresh();Nexus.Panel.Show()
 check(has(texts(NexusPanel),'Assigned Wishlist is unavailable') and not has(texts(NexusPanel),EMPTY_NOTE),'and the HUD is unchanged')
end
-- 3h. Explicit Unassign on the empty slot: the gear is off, the wording is still the empty-slot wording.
reopen(emptyRow(),2,function(d) eachRow(d,function(r) if r.firstRunWishlist~=nil then r.firstRunWishlist=false end end) end)
do
 check(firstRun()==false,'precondition: explicit Unassign marker')
 journal()
 check(not NexusAssociatedWishlistDesignButton:IsEnabled(),'no first-run plan: the gear is disabled')
 check(has(Hover(NexusActiveWishlistSelector),'This Saved Build is empty, so no Wishlist can be assigned to it'),'the selector tooltip still tells the truth')
 local r=Nexus.GameAdapter.AssignedWishlist()
 check(r.state=='unassigned' and r.emptySlot==true and r.name==nil,'explicit Unassign on an empty slot: unassigned')
end

-- 4. The open picker's words follow the target it opened for (the same one its click
-- handlers captured), not the live Journal context. The context can change while the
-- picker stays open: the active Saved Build switches and the Journal refreshes.
local STD_ROW='Sets this Wishlist as the target for this loadout.'
local EMPTY_ROW='refused until it holds Echoes'
local STD_UNASSIGN='Keeps the Wishlist; stops using it for this loadout.'
local EMPTY_UNASSIGN='This does not remove the first-run Wishlist.'
local function spyClears()
 local A=Nexus.GameAdapter
 local log={loadout={},first=0}
 local rawL,rawF=A.ClearLoadoutWishlist,A.ClearFirstRunWishlist
 A.ClearLoadoutWishlist=function(slot,...) log.loadout[#log.loadout+1]=slot;return rawL(slot,...) end
 A.ClearFirstRunWishlist=function(...) log.first=log.first+1;return rawF(...) end
 return log
end
local function switchTo(slot,row)
 H.perks.serverActiveSlot=slot
 if row then H.perks.serverBuildSlots[slot]=row end
 Nexus.JournalTab.RefreshAssociations()
end
local function liveEmpty() return NexusActiveWishlistSelector:GetParent().emptySlot end
-- Boot at `startSlot`, open the picker, switch the live context to `endSlot` while it stays open.
local function transition(tag,startRow,startSlot,endSlot,endRow,mutate)
 reopen(startRow,startSlot,mutate)
 local p=openPicker()
 local log=spyClears()
 local before=snapshot()
 switchTo(endSlot,endRow)
 check(p:IsShown(),tag..': the picker stays open across the refresh')
 return p,log,before
end

-- 4a. Opened at slot 0 (first-run target), the context becomes a known-empty Saved Build.
do
 local p,log,before=transition('4a',nil,0,2,emptyRow())
 check(liveEmpty()==true,'4a: the live Journal context is now the empty Saved Build')
 local rowTip=Hover(pickerRow(p).nameButton)
 check(has(rowTip,'Target: No Saved Build selected') and has(rowTip,STD_ROW) and not has(rowTip,EMPTY_ROW),
  '4a: the row tooltip keeps the target it opened for: '..rowTip)
 local unTip=Hover(p.clearRow)
 check(has(unTip,STD_UNASSIGN) and not has(unTip,EMPTY_UNASSIGN),'4a: the Unassign tooltip does not promise the first-run plan is kept: '..unTip)
 p.clearRow:GetScript('OnClick')(p.clearRow)
 check(log.first==1 and #log.loadout==0,'4a: Unassign still clears the first-run plan (its captured target)')
 check(type(firstRun())~='table' and Nexus.Store.State().loadoutWishlists[2]==nil,'4a: the first-run plan is cleared and slot 2 is untouched')
end
do -- 4a'. The same transition, picker row selection: still the captured first-run target.
 local p=transition('4a-row',nil,0,2,emptyRow())
 pickerRow(p).nameButton:Click()
 check(not said('empty or unavailable'),'4a-row: selecting the first-run plan is not refused')
 check(Nexus.Store.State().loadoutWishlists[2]==nil,'4a-row: nothing is assigned to the empty slot')
end
-- 4b. Opened at an empty Saved Build, the live context becomes slot 0.
do
 local p,log=transition('4b',emptyRow(),2,0)
 check(liveEmpty()~=true,'4b: the live Journal context is no longer the empty Saved Build')
 local rowTip=Hover(pickerRow(p).nameButton)
 check(has(rowTip,'Target: Empty Saved Build slot') and has(rowTip,EMPTY_ROW) and not has(rowTip,STD_ROW),'4b: the row tooltip keeps the empty-slot wording: '..rowTip)
 local unTip=Hover(p.clearRow)
 check(has(unTip,EMPTY_UNASSIGN) and not has(unTip,STD_UNASSIGN),'4b: the Unassign tooltip keeps the empty-slot wording: '..unTip)
 p.clearRow:GetScript('OnClick')(p.clearRow)
 check(#log.loadout==1 and log.loadout[1]==2 and log.first==0,'4b: Unassign still clears the numbered slot only')
 check(type(firstRun())=='table','4b: the first-run plan is kept')
end
do
 local p=transition('4b-row',emptyRow(),2,0)
 local before=snapshot()
 pickerRow(p).nameButton:Click()
 check(said('empty or unavailable') and T.Equal(before,snapshot()),'4b-row: selection is still refused for the numbered slot and changes no record')
end
-- 4c. Opened at an empty Saved Build, the live context becomes a populated one.
do
 local p,log=transition('4c',emptyRow(),2,3,populatedRow())
 check(liveEmpty()~=true,'4c: the live Journal context is a populated Saved Build')
 check(has(Hover(pickerRow(p).nameButton),EMPTY_ROW) and has(Hover(p.clearRow),EMPTY_UNASSIGN),'4c: both tooltips keep the empty-slot wording')
 p.clearRow:GetScript('OnClick')(p.clearRow)
 check(#log.loadout==1 and log.loadout[1]==2 and log.first==0 and type(firstRun())=='table','4c: Unassign still targets slot 2 and keeps the first-run plan')
end
-- 4d. Opened at a populated Saved Build (with its association), the live context becomes an empty one.
do
 local p,log=transition('4d',populatedRow(),2,3,emptyRow())
 check(liveEmpty()==true,'4d: the live Journal context is an empty Saved Build')
 local rowTip=Hover(pickerRow(p).nameButton)
 check(has(rowTip,STD_ROW) and not has(rowTip,EMPTY_ROW) and has(Hover(p.clearRow),STD_UNASSIGN),'4d: both tooltips keep the populated wording')
 check(Nexus.Store.State().loadoutWishlists[2]~=nil,'4d: precondition: slot 2 holds the handed-off association')
 p.clearRow:GetScript('OnClick')(p.clearRow)
 check(#log.loadout==1 and log.loadout[1]==2 and log.first==0 and Nexus.Store.State().loadoutWishlists[2]==nil,'4d: Unassign still clears the association of slot 2')
end
-- 4e. Opened at an empty Saved Build, the active slot becomes unknown.
do
 local p=transition('4e',emptyRow(),2,nil)
 check(has(Hover(pickerRow(p).nameButton),EMPTY_ROW) and has(Hover(p.clearRow),EMPTY_UNASSIGN),'4e: both tooltips keep the empty-slot wording')
end
-- 4f. Reopening the picker takes the new context, with its own target.
do
 local p,log=transition('4f',nil,0,2,emptyRow())
 NexusActiveWishlistSelector:Click()
 check(not p:IsShown(),'4f: the selector closes the open picker')
 NexusActiveWishlistSelector:Click()
 check(p:IsShown(),'4f: and reopens it for the new context')
 check(has(Hover(pickerRow(p).nameButton),EMPTY_ROW) and has(Hover(p.clearRow),EMPTY_UNASSIGN),'4f: reopened tooltips use the empty-slot wording')
 p.clearRow:GetScript('OnClick')(p.clearRow)
 check(#log.loadout==1 and log.loadout[1]==2 and log.first==0 and type(firstRun())=='table','4f: the reopened Unassign targets slot 2 and keeps the first-run plan')
end

print=function(...) io.write(table.concat((function(...)local t={};for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end;return t end)(...),'\t'),'\n') end
print('PASS empty_saved_build_journal_text: '..checks..' checks (Journal gear, selector, row and Unassign tooltips, assignment note, HUD and Orb text for an empty Saved Build with a first-run plan; actions, refusals and records unchanged; populated, slot-zero, unavailable, unknown-data and explicit-Unassign controls)')
