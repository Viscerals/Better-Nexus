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

-- Stale open rows: the server changes after the picker was built. Each click
-- must use the row's own snapshot, so the row keeps the closure it was built with.
local function server(rows)
 for slot=101,110 do H.perks.serverBuildSlots[slot]=nil end
 for slot,r in pairs(rows)do
  H.perks.serverBuildSlots[slot]={name=r[1],verified=false,echoes=H.Clone(r[2])}
 end
 H.Notify();A.Poll()
end
local function variant(n)
 local e=H.Clone(rolled);e[1].spellId=e[1].spellId+500+n;return e
end
local function staleRow(name,rows)
 local p=open();local r=assert(row(p,name),'actual picker has '..name)
 local click=r.nameButton:GetScript('OnClick')
 server(rows)
 assert(p:IsShown() and r.nameButton:GetScript('OnClick')==click,'SETUP: the open row keeps its snapshot')
 return p,r
end
local function refused(p,r,context,text,label)
 local before=H.Clone(saved(context))
 local messages={}
 local originalPrint=print
 print=function(...)
  local parts={};for i=1,select('#',...)do parts[#parts+1]=tostring((select(i,...)))end
  messages[#messages+1]=table.concat(parts,' ')
  originalPrint(...)
 end
 r.nameButton:Click()
 print=originalPrint
 local found=false
 for _,m in ipairs(messages)do if m:find(text,1,true)then found=true end end
 print('EQUAL_CONTENT_REFUSAL',label,'refused',found,'savedSlot',saved(context) and saved(context).slot)
 assert(found,label..': refused with "'..text..'"')
 assert(p:IsShown(),label..': a refused selection keeps the picker open')
 assert(T.Equal(before,saved(context)),label..': a refused selection keeps the stored assignment')
 assert(#H.actions==actions and H.Count('orb-spend')==0,label..': no gameplay or service mutation')
end
for _,context in ipairs({2,0})do
 H.perks.serverActiveSlot=context;H.Notify();A.Poll()
 server({[101]={'Plan A',rolled},[102]={'Plan B',rolled},[103]={'Plan C',rolled}})
 pick('Plan C',103,context)
 -- The clicked slot still exists with other contents while equal contents
 -- remain in two other slots: refuse; never redirect by content.
 local p,r=staleRow('Plan B',{[101]={'Plan A',rolled},[102]={'Plan B',variant(1)},[103]={'Plan C',rolled}})
 refused(p,r,context,'wishlist changed; refresh and try again','changed clicked slot, context '..context)
 -- The same, with exactly one equal-content Wishlist elsewhere and under the
 -- clicked name: still refused, never redirected by contents or name.
 server({[101]={'Plan A',variant(2)},[102]={'Plan B',rolled},[103]={'Plan C',variant(3)}})
 p,r=staleRow('Plan B',{[101]={'Plan A',variant(2)},[102]={'Plan B',variant(1)},[103]={'Plan C',variant(3)},[104]={'Plan B',rolled}})
 refused(p,r,context,'wishlist changed; refresh and try again','changed clicked slot, one same-name match elsewhere, context '..context)
 -- The clicked slot keeps its contents under a new name: it is still the
 -- clicked Wishlist.
 server({[101]={'Plan A',variant(2)},[102]={'Plan B',rolled},[103]={'Plan C',variant(3)}})
 pick('Plan C',103,context)
 p,r=staleRow('Plan B',{[101]={'Plan A',variant(2)},[102]={'Plan B2',rolled},[103]={'Plan C',variant(3)}})
 r.nameButton:Click()
 local a,record=A.AssignedWishlist(),saved(context)
 print('EQUAL_CONTENT_RENAMED','context',context,'assigned',a.name,'savedSlot',record and record.slot)
 assert(not p:IsShown() and a.state=='ready' and a.name=='Plan B2','renamed clicked slot is assigned')
 assert(record.slot==102 and record.key==k,'renamed clicked slot keeps its slot')
 -- The clicked slot is gone and exactly one live Wishlist has its contents,
 -- under another name: follow the moved identity.
 server({[101]={'Plan A',variant(2)},[102]={'Plan B',rolled},[103]={'Plan C',variant(3)}})
 pick('Plan C',103,context)
 p,r=staleRow('Plan B',{[101]={'Plan A',variant(2)},[103]={'Plan C',variant(3)},[104]={'Plan E',rolled}})
 r.nameButton:Click()
 a,record=A.AssignedWishlist(),saved(context)
 print('EQUAL_CONTENT_MOVED','context',context,'assigned',a.name,'savedSlot',record and record.slot)
 assert(not p:IsShown(),'unique moved identity: selection closes the picker')
 assert(a.state=='ready' and a.activeSlot==context and a.name=='Plan E','unique moved identity is assigned')
 assert(record.slot==104 and record.name=='Plan E' and record.key==k,'unique moved identity stores its new slot')
 assert(#H.actions==actions and H.Count('orb-spend')==0,'unique moved identity: no gameplay or service mutation')
 -- The clicked slot is gone and two live Wishlists have its contents, one of
 -- them under the same name: ambiguous. Neither list order nor name decides.
 server({[101]={'Plan A',variant(2)},[102]={'Plan B',rolled},[103]={'Plan C',variant(3)}})
 pick('Plan C',103,context)
 p,r=staleRow('Plan B',{[101]={'Plan A',variant(2)},[103]={'Plan C',variant(3)},[105]={'Plan B',rolled},[106]={'Plan D',rolled}})
 refused(p,r,context,'wishlist identity is ambiguous; refresh and try again','ambiguous moved identity, context '..context)
end
print('PASS equal-content Wishlists assign the clicked slot in numbered and first-run contexts; changed slots stay refused; a moved identity is followed only when unique')
