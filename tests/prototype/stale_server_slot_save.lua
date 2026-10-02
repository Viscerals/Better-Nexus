-- W16: an open editor must not upload to a server Wishlist slot that was reused.
-- The editor binds the opened Wishlist's server slot S. Saving used to upload the
-- frozen payload to S even when the slot service then showed another Wishlist
-- (or nothing) at S, after a confirmation delay or on a spacing retry.
-- Counted host upload calls are the oracle. Synthetic mirrors only; no real account or game access.
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

-- A first-run plan made through the real editor; the server mirror then holds it at slot 102.
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

-- Another Wishlist B, and a variant of A with different content.
local B_ROWS={{spellId=200768,quality=0,stacks=2}}
local A2_ROWS=H.Clone(planRows);A2_ROWS[#A2_ROWS+1]={spellId=200768,quality=0,stacks=1}

local function open()
 H=boot(H.Clone(saved),{[102]=H.Clone(MIRROR_A)})
 notices={}
 journal()
 check(NexusAssociatedWishlistDesignButton:IsEnabled(),'the first-run plan can be opened')
 NexusAssociatedWishlistDesignButton:Click()
 selected(201172).plus:Click() -- the edit: one more copy
end
local function setMirror(slot,value) H.perks.serverBuildSlots[slot]=value and H.Clone(value) or nil;H.Notify() end
local function refused(label,extra)
 check(uploadsTo(102)==0,label..': nothing is uploaded to the reused slot')
 check(said('no longer holds'),label..': the refusal is explained')
 check(pcall(selected,201172) and selected(201172).data.stacks==2,label..': the edited draft is still shown')
 if extra then extra() end
end

-- 1. Unchanged slot: exactly one upload, to that slot.
open()
do
 local before=snapshot()
 button('Save Wishlist'):Click()
 check(H.popup and H.popup.which=='WISHLISTREALIZER_UPDATE_WISHLIST','the confirmation is offered')
 H.AcceptPopup();H.Advance(4)
 check(uploadsTo(102)==1 and #H.actions==1,'an unchanged slot receives the one upload')
 check(not said('no longer holds'),'and no refusal is shown')
end

-- 2. The slot is reused before Save: another Wishlist B (name and content differ).
open()
do
 local before=snapshot()
 setMirror(102,row('Someone Elses Plan',B_ROWS))
 button('Save Wishlist'):Click()
 check(H.popup==nil,'no confirmation is offered for a reused slot')
 refused('reused before Save',function()
  check(T.Equal(before,snapshot()),'assignments and the first-run plan are untouched')
  check(H.perks.serverBuildSlots[102].name=='Someone Elses Plan','and the other Wishlist is untouched')
 end)
end

-- 3. The slot is reused while the confirmation is open.
open()
do
 local before=snapshot()
 button('Save Wishlist'):Click()
 check(H.popup and H.popup.which=='WISHLISTREALIZER_UPDATE_WISHLIST','precondition: the confirmation is open')
 setMirror(102,row('Someone Elses Plan',B_ROWS))
 H.AcceptPopup();H.Advance(4)
 refused('reused during the confirmation',function() check(T.Equal(before,snapshot()),'state is untouched') end)
end

-- 4. The slot is reused while the save waits on the upload spacing.
open()
do
 check(Nexus.GameAdapter.UploadWishlist(103,'W16-SPACER',{{spellId=200768,quality=0,stacks=1}})==true,'fixture: a recent upload starts the spacing window')
 local before=snapshot()
 button('Save Wishlist'):Click();H.AcceptPopup()
 check(Nexus.WishlistEditor.IsApplyPending()==true,'precondition: the save waits for the spacing')
 setMirror(102,row('Someone Elses Plan',B_ROWS))
 Nexus.WishlistEditor._PumpApplyRetry()
 check(Nexus.WishlistEditor.IsApplyPending()==false,'the queued retry is dropped')
 refused('reused during the retry wait',function()
  check(#H.actions==1 and H.actions[1][2]==103,'only the fixture upload was ever sent')
  check(T.Equal(before,snapshot()),'state is untouched')
 end)
end

-- 5. Name and content are each compared: neither alone proves the slot is still the opened Wishlist.
for _,case in ipairs({
 {tag='same name, different content',mirror=row(NAME,A2_ROWS)},
 {tag='different name, same content',mirror=row('Renamed By Someone',planRows)},
 {tag='removed',mirror=false},
 {tag='present without Echoes',mirror=row(NAME,{})},
})do
 open()
 setMirror(102,case.mirror)
 button('Save Wishlist'):Click()
 if H.popup then H.AcceptPopup();H.Advance(4) end
 refused(case.tag)
end

-- 6. ABA. The slot goes A -> B -> A2 (another record with A's name, different content): refused.
open()
do
 setMirror(102,row('Someone Elses Plan',B_ROWS))
 H.Advance(1)
 setMirror(102,row(NAME,A2_ROWS))
 button('Save Wishlist'):Click()
 if H.popup then H.AcceptPopup();H.Advance(4) end
 refused('A then B then a different A2')
end
-- A -> removed -> recreated with the same name and the same content: the mirror cannot tell it from A,
-- and the upload replaces equal content. This limit is documented, not claimed as identity proof.
open()
do
 setMirror(102,false);H.Advance(1)
 setMirror(102,MIRROR_A)
 button('Save Wishlist'):Click();H.AcceptPopup();H.Advance(4)
 check(uploadsTo(102)==1,'an identical re-creation is indistinguishable from the opened Wishlist and replaces equal content')
end

-- 7. Two consecutive saves in one editor session stay supported, with or without the mirror catching up.
for _,catchUp in ipairs({false,true})do
 open()
 button('Save Wishlist'):Click();H.AcceptPopup();H.Advance(4)
 check(uploadsTo(102)==1,'first own save uploaded')
 if catchUp then
  local own=H.Clone(H.actions[#H.actions][4])
  setMirror(102,row(NAME,own));Nexus.GameAdapter.Poll();H.Advance(1)
 end
 selected(201172).plus:Click()
 button('Save Wishlist'):Click()
 check(H.popup~=nil,'the second save is offered'..(catchUp and ' after the mirror caught up' or ' before the mirror caught up'))
 H.AcceptPopup();H.Advance(4)
 check(uploadsTo(102)==2,'the second own save uploads too')
 -- and a foreign record after that is still refused
 setMirror(102,row('Someone Elses Plan',B_ROWS))
 selected(201172).plus:Click()
 H.Advance(4)
 button('Save Wishlist'):Click()
 if H.popup then H.AcceptPopup();H.Advance(4) end
 check(uploadsTo(102)==2,'a foreign record after own saves is refused')
end

-- 8. Adapter level: a caller that skips the editor and names the identities it accepts.
open()
do
 local A=Nexus.GameAdapter
 local before=#H.actions
 local token=A.ServerWishlistSlotToken(102)
 check(type(token)=='string','the slot has an observable identity token')
 setMirror(102,row('Someone Elses Plan',B_ROWS))
 local ok,why=A.UploadWishlist(102,NAME,planRows,{[token]=true})
 check(ok==false and why=='stale_slot' and #H.actions==before,'the adapter refuses a stale slot before the host call: '..tostring(why))
 setMirror(102,false)
 ok,why=A.UploadWishlist(102,NAME,planRows,{[token]=true})
 check(ok==false and why=='stale_slot' and #H.actions==before,'the adapter refuses a slot that shows nothing too: '..tostring(why))
 H.Advance(4)
 check(A.UploadWishlist(102,NAME,planRows)==true and #H.actions==before+1,'a caller that names no identity is unchanged')
 H.Advance(4)
 check(A.UploadWishlist(0,'W16-CREATE',planRows,{[token]=true})==true,'the create sentinel 0 is never checked')
end

-- 9. A new Wishlist and a controller whose adapter cannot name slot identities are not guarded.
open()
do
 local A=Nexus.GameAdapter
 local adapter={};for k,v in pairs(A) do adapter[k]=v end
 adapter.ServerWishlistSlotToken=nil
 local c=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=Nexus.Store,
  accountRoot=function() return {} end,notify=function() end})
 c.Initialize(adapter)
 local wishlist={slot=102,name=NAME,key=A.WishlistKey(planRows),echoes=planRows}
 check(c.BeginWishlist(wishlist,nil)==true,'a controller opens the Wishlist')
 setMirror(102,row('Someone Elses Plan',B_ROWS))
 local data,why=c.PrepareApply()
 check(data~=nil,'without slot identities in the adapter the controller keeps its former behavior: '..tostring(why))
end
-- The controller's own check, with an adapter whose upload ignores the accepted set: it alone must refuse.
open()
do
 local A=Nexus.GameAdapter
 local before=#H.actions
 local adapter={};for k,v in pairs(A) do adapter[k]=v end
 adapter.UploadWishlist=function(slot,name,echoes) -- ignores `expected`
  return A.UploadWishlist(slot,name,echoes)
 end
 for _,case in ipairs({{tag='replaced',mirror=row('Someone Elses Plan',B_ROWS)},{tag='removed',mirror=false}})do
  H.Advance(4)
  local c=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=Nexus.Store,
   accountRoot=function() return {} end,notify=function() end})
  c.Initialize(adapter)
  setMirror(102,MIRROR_A)
  local wishlist={slot=102,name=NAME,key=A.WishlistKey(planRows),echoes=planRows}
  check(c.BeginWishlist(wishlist,nil)==true,case.tag..': the controller opens the Wishlist')
  setMirror(102,case.mirror)
  local ok,reason=c.AcceptApply(102,NAME,planRows)
  check(ok==false and reason=='stale_slot' and #H.actions==before,case.tag..': the controller alone refuses, nothing is uploaded: '..tostring(reason))
 end
end
-- missing identity at open: the slot has no observable row when the editor opens
open()
do
 local A=Nexus.GameAdapter
 local c=Nexus.WishlistInternals.Controller.New({model=Nexus.WishlistModel.New(),store=Nexus.Store,
  accountRoot=function() return {} end,notify=function() end})
 c.Initialize(A)
 setMirror(102,false)
 local wishlist={slot=102,name=NAME,key=A.WishlistKey(planRows),echoes=planRows}
 check(c.BeginWishlist(wishlist,nil)==true,'a controller opens a Wishlist whose slot is not in the mirror')
 setMirror(102,MIRROR_A)
 local data,why=c.PrepareApply()
 check(data==nil and why=='stale_slot','an identity that was missing at open authorizes nothing: '..tostring(why))
 local ok,reason=c.AcceptApply(102,NAME,planRows)
 check(ok==false and reason=='stale_slot','the direct payload path is refused and reports failure: '..tostring(ok)..'/'..tostring(reason))
 check(uploadsTo(102)==0,'and nothing was uploaded')
end

print=rawPrint
print('PASS stale_server_slot_save: '..checks..' checks (reuse before Save, during confirmation, during retry; name/content/missing; ABA; consecutive saves; adapter; compatibility)')
