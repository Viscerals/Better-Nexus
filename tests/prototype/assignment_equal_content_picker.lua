-- Two server Wishlists with equal rolled contents are still distinct choices.
-- Drive the actual Journal picker rows: each click must assign its own server
-- slot, never the first mirror whose rolled contents happen to match.
local originalDofile=dofile
local H
dofile=function(path)
 local result=originalDofile(path)
 if path=='tests/prototype/orbs_support.lua' then H=result end
 return result
end
dofile('tests/prototype/assignment_journal_picker.lua')
dofile=originalDofile
assert(H)
local T=dofile('tests/prototype/startup_support.lua')
local A=Nexus.GameAdapter
local actions=#H.actions
local rolled=H.Clone(H.perks.serverBuildSlots[101].echoes)
H.perks.serverBuildSlots[103]={name='Plan C',verified=false,echoes=H.Clone(rolled)}
H.Notify();A.Poll()
local function open()
 ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
 if NexusWishlistOnlyPicker:IsShown() then NexusActiveWishlistSelector:Click() end
 NexusActiveWishlistSelector:Click()
 assert(NexusWishlistOnlyPicker:IsShown(),'actual selector opens its picker')
 return NexusWishlistOnlyPicker
end
local function row(p,name)
 for _,r in ipairs(p.children)do
  if r.nameButton and r:IsVisible() and r.nameButton.text:GetText():find(name,1,true)then return r end
 end
end
local function plain(slot)
 for _,c in ipairs(A.GetWishlistCandidates())do
  if c.slot==slot then return c.designTargets==nil end
 end
end
local function saved(context)
 local state=Nexus.Store.State()
 if context==0 then return state.firstRunWishlist end
 return state.loadoutWishlists[context]
end
local function pick(name,slot,context)
 local p=open()
 local r=assert(row(p,name),'actual picker has '..name)
 r.nameButton:Click()
 local a,record=A.AssignedWishlist(),saved(context)
 print('EQUAL_CONTENT_PICK','context',context,'clicked',name,'assigned',a.name,'savedSlot',record and record.slot,'savedName',record and record.name)
 assert(not p:IsShown(),'successful selection closes the picker')
 assert(a.state=='ready' and a.activeSlot==context,'selection resolves in the active context')
 assert(a.name==name,'clicked '..name..' but assigned '..tostring(a.name))
 assert(record.slot==slot and record.name==name,'stored assignment keeps the clicked server slot')
end
local k=A.WishlistKey(rolled)
for _,slot in ipairs({101,102,103})do
 assert(A.WishlistKey(H.perks.serverBuildSlots[slot].echoes)==k,'SETUP: rolled contents are identical')
end
-- Numbered Saved Build context. Leaving the previous Plan B design turns the
-- Plan B row into a plain server row: the path that must not merge by content.
assert(H.perks.serverActiveSlot==2,'SETUP: numbered Saved Build is active')
pick('Plan A',101,2)
assert(plain(102) and plain(103),'SETUP: Plan B and Plan C rows are plain server rows')
pick('Plan B',102,2);pick('Plan C',103,2);pick('Plan B',102,2)
-- The first-run context shares the same selection boundary.
H.perks.serverActiveSlot=0;H.Notify();A.Poll()
pick('Plan B',102,0);pick('Plan C',103,0)
-- An open picker row whose slot changed and whose contents exist nowhere else
-- is still refused, and the refusal leaves the assignment untouched.
local p=open();local stale=assert(row(p,'Plan B'),'actual picker has Plan B')
local changed=H.Clone(rolled);changed[1].spellId=changed[1].spellId+500
local before=H.Clone(saved(0))
H.perks.serverBuildSlots[101],H.perks.serverBuildSlots[103]=nil,nil
H.perks.serverBuildSlots[102]={name='Plan B',verified=false,echoes=changed}
H.Notify();A.Poll()
local messages={}
local originalPrint=print
print=function(...)
 local parts={};for i=1,select('#',...)do parts[#parts+1]=tostring((select(i,...)))end
 messages[#messages+1]=table.concat(parts,' ')
 originalPrint(...)
end
stale.nameButton:Click()
print=originalPrint
local refused=false
for _,m in ipairs(messages)do if m:find('wishlist changed; refresh and try again',1,true)then refused=true end end
assert(refused,'changed server slot is still refused')
assert(p:IsShown(),'a refused selection keeps the picker open')
assert(T.Equal(before,saved(0)),'a refused selection keeps the stored assignment')
assert(#H.actions==actions and H.Count('orb-spend')==0,'picker selection submits no gameplay or service mutation')
print('PASS equal-content Wishlists assign the clicked slot in numbered and first-run contexts; changed slots stay refused')
