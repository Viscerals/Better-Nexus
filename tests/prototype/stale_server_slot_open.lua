-- W16 repair: the identity an editor may overwrite is the SELECTED record, bound before the
-- Journal / role-picker / editor transitions, never the row the slot service shows when the
-- editor opens. A contradiction seen is not undone by the selection reappearing; a row the
-- adapter could only partly read has no identity; an upload is bookkept against the editor
-- that submitted it. Counted host upload calls are the oracle. Synthetic mirrors only.
local T=dofile('tests/prototype/startup_support.lua')
local NAME='W16-PLAN'
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
local function boot(saved,slots)
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
 h.AddEcho(200768,'Arcane Blast',0,5)
 h.perks.serverActiveSlot=0
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
local function snapshot() return H.Clone(Nexus.Store.State()) end
local function uploadsTo(slot)
 local n=0
 for _,a in ipairs(H.actions) do if a[1]=='upload' and a[2]==slot then n=n+1 end end
 return n
end

-- A first-run plan (ordinary 201172 plus a locked design target) made through the real editor;
-- the server mirror then holds its ordinary rows at slot 102.
journal();button('New Wishlist'):Click()
catalog(201172):Click()
local emptySlot
for _,f in ipairs(H.frames)do if f:IsVisible() and f.slotState=='empty' then emptySlot=f;break end end
emptySlot:Click();catalog(200767):Click()
_G.NexusWishlistNameInput:SetText(NAME)
button('Create Wishlist'):Click();H.AcceptPopup()
local planRows=H.Clone(H.actions[1][4])
local function row(name,rows) return {name=name,verified=false,echoes=H.Clone(rows)} end
local MIRROR_A=row(NAME,planRows)
H.perks.serverBuildSlots={[102]=H.Clone(MIRROR_A)};H.Notify();Nexus.GameAdapter.Poll();H.Advance(4)
local saved=H.Clone(NexusDB)

local B_ROWS={{spellId=200768,quality=0,stacks=2}}
local A2_ROWS=H.Clone(planRows);A2_ROWS[#A2_ROWS+1]={spellId=200768,quality=0,stacks=1}
-- No notification: the Journal row stays as it was built.
local function rawSet(slot,value) H.perks.serverBuildSlots[slot]=value and H.Clone(value) or nil end
local function pickerGear()
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f.glyph and f:IsVisible() and f~=NexusAssociatedWishlistDesignButton then
   local parent=f:GetParent()
   local label=parent and parent.nameButton and parent.nameButton.text and parent.nameButton.text:GetText() or ''
   if label:find(NAME,1,true) then return f end
  end
 end
 error('picker gear absent')
end
-- The Journal picker row is built from mirror A; the slot may change; then the gear is clicked.
local function openFromRow(changeSlot)
 H=boot(H.Clone(saved),{[102]=H.Clone(MIRROR_A)})
 notices={}
 journal()
 NexusActiveWishlistSelector:Click()
 local gear=pickerGear()
 if changeSlot then changeSlot() end
 gear:Click()
 selected(201172).plus:Click()
end
local function saveAttempt()
 button('Save Wishlist'):Click()
 if H.popup then H.AcceptPopup();H.Advance(4) end
end

-- 1. Row A captured, the slot is reused before the gear is clicked: the editor does not bind B.
for _,case in ipairs({
 {tag='another Wishlist',mirror=row('Someone Elses Plan',B_ROWS)},
 {tag='same title, different counts',mirror=row(NAME,A2_ROWS)},
 {tag='different title, same counts',mirror=row('Renamed By Someone',planRows)},
})do
 openFromRow(function() rawSet(102,case.mirror) end)
 local before=snapshot()
 saveAttempt()
 check(uploadsTo(102)==0,case.tag..': no upload to the reused slot')
 check(said('no longer holds'),case.tag..': the refusal is explained')
 check(pcall(selected,201172) and selected(201172).data.stacks==2,case.tag..': the draft of the selected Wishlist is kept')
 check(T.Equal(before,snapshot()),case.tag..': assignments and the first-run plan are untouched')
 -- the selection reappearing does not give the overwrite back
 rawSet(102,MIRROR_A)
 saveAttempt()
 check(uploadsTo(102)==0,case.tag..': the selection reappearing in the slot does not authorize the upload')
end

-- 2. Unknown is not a contradiction: no readable row at the click, the selection shown when saving.
openFromRow(function() rawSet(102,false) end)
check(uploadsTo(102)==0,'precondition: nothing uploaded')
rawSet(102,MIRROR_A)
saveAttempt()
check(uploadsTo(102)==1,'a slot that could not be read at the click and then shows the selection can be saved')

-- 3. Partial or unreadable rows have no identity, even when the readable part equals the selection.
do
 local valid=H.Clone(planRows)
 local dense=H.Clone(valid);dense[#dense+1]={spellId='unreadable',quality=0,stacks=1}
 local sparse={};sparse[1]=H.Clone(valid[1]);sparse[3]={spellId=200768,quality=0,stacks=1}
 for _,case in ipairs({{tag='dense row with an unreadable entry',rows=dense,dense=true},{tag='sparse row',rows=sparse}})do
  openFromRow()
  local before=snapshot()
  local goodToken=Nexus.GameAdapter.ServerWishlistSlotToken(102)
  check(type(goodToken)=='string','precondition: the intact row has a token')
  rawSet(102,{name=NAME,verified=false,echoes=case.rows})
  check(Nexus.GameAdapter.ServerWishlistSlotToken(102)==nil,case.tag..': the adapter gives it no token')
  if case.dense then
   check(#Nexus.GameAdapter.Slots().bySlot[102].echoes==#valid,'the unreadable entry is dropped from the projection, so the survivors equal the selection')
  end
  saveAttempt()
  check(uploadsTo(102)==0,case.tag..': zero uploads')
  check(Nexus.GameAdapter.UploadWishlist(102,NAME,planRows,{[goodToken]=true})==false,case.tag..': the adapter refuses it as well')
  check(T.Equal(before,snapshot()),case.tag..': state untouched')
 end
end

-- 4. A replacement the guard saw stays seen, and reopening is a fresh selection.
openFromRow()
do
 rawSet(102,row('Someone Elses Plan',B_ROWS))
 saveAttempt()
 check(uploadsTo(102)==0,'B observed by the guard: refused')
 rawSet(102,MIRROR_A)
 saveAttempt()
 check(uploadsTo(102)==0,'A reappears: the old binding does not regain overwrite authority')
 check(said('no longer holds'),'and says why')
 H.Advance(4)
 NexusAssociatedWishlistDesignButton:Click() -- reopen: a new selection
 selected(201172).plus:Click()
 saveAttempt()
 check(uploadsTo(102)==1,'a fresh selection of the unchanged Wishlist saves')
end

-- 5. An upload belongs to the editor that submitted it: a callback that opens another editor
-- during the host call does not give that editor the submitted content as an accepted state.
do
 H=boot(H.Clone(saved),{[102]=H.Clone(MIRROR_A),[103]=row('Other Plan',B_ROWS)})
 notices={}
 journal()
 NexusAssociatedWishlistDesignButton:Click()
 selected(201172).plus:Click()
 local submit=H.service.UploadServerBuildSlot
 local submitted
 H.service.UploadServerBuildSlot=function(slot,name,entries)
  local ok=submit(slot,name,entries)
  submitted=H.Clone(entries)
  Nexus.WishlistEditor.OpenForWishlist({slot=103,name='Other Plan',key=Nexus.GameAdapter.WishlistKey(B_ROWS),echoes=H.Clone(B_ROWS)},nil)
  return ok
 end
 button('Save Wishlist'):Click();H.AcceptPopup();H.Advance(4)
 H.service.UploadServerBuildSlot=submit
 check(uploadsTo(102)==1 and submitted~=nil,'the submitting editor uploaded once')
 local before103=uploadsTo(103)
 -- slot 103 now shows the content the first editor submitted, under that editor's name
 H.perks.serverBuildSlots[103]=row(NAME,submitted)
 selected(200768).plus:Click()
 H.Advance(4)
 button('Save Wishlist'):Click()
 if H.popup then H.AcceptPopup();H.Advance(4) end
 check(uploadsTo(103)==before103,'the other editor does not inherit the submitted state: nothing is uploaded to 103')
end

-- 6. A local locked design differing from the ordinary host projection is supported.
do
 H=boot(H.Clone(saved),{[102]=H.Clone(MIRROR_A)})
 journal()
 local first=Nexus.Store.State().firstRunWishlist
 check(first and type(first.designRows)=='table' and next(first.designRows)~=nil,'fixture: the first-run plan carries a locked design the host row does not')
 NexusAssociatedWishlistDesignButton:Click()
 selected(201172).plus:Click()
 saveAttempt()
 check(uploadsTo(102)==1,'the edit saves although the design is not in the host projection')
 local after=Nexus.Store.State().firstRunWishlist
 check(after and type(after.designRows)=='table' and next(after.designRows)~=nil,'and the locked design is kept')
 -- changed ordinary source before open: no name-only bypass
 H=boot(H.Clone(saved),{[102]=H.Clone(MIRROR_A)})
 notices={}
 journal()
 rawSet(102,row(NAME,A2_ROWS)) -- same title, other ordinary content
 NexusAssociatedWishlistDesignButton:Click()
 selected(201172).plus:Click()
 saveAttempt()
 check(uploadsTo(102)==0,'same title with changed ordinary content: zero uploads although the plan has a design')
end

print=rawPrint
print('PASS stale_server_slot_open: '..checks..' checks (row captured, unknown vs contradiction, partial rows, latch, submitting editor, locked design)')
