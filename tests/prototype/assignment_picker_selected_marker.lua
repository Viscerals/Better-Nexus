-- The Journal picker marks exactly the resolved assignment with [Selected].
-- Drives the real selector and picker rows over equal-content server Wishlists:
-- the marker follows the current resolved server slot and content key (or an
-- equal assignmentId), never equal contents in another slot and never a name.
-- Display only: opening and reading the picker assigns, saves and spends nothing.
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
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local actions=#H.actions
local rolled=H.Clone(H.perks.serverBuildSlots[101].echoes)
local k=A.WishlistKey(rolled)

local function open()
 ProjectEbonholdEchoJournal:Show();Nexus.JournalTab.RefreshAssociations()
 if NexusWishlistOnlyPicker:IsShown() then NexusActiveWishlistSelector:Click() end
 NexusActiveWishlistSelector:Click()
 check(NexusWishlistOnlyPicker:IsShown(),'actual selector opens its picker')
 return NexusWishlistOnlyPicker
end
local function close()
 if NexusWishlistOnlyPicker:IsShown() then NexusActiveWishlistSelector:Click() end
end
local function rows(p)
 local out={}
 for _,r in ipairs(p.children)do
  if r.nameButton and r:IsVisible() then out[#out+1]=r end
 end
 return out
end
local function row(p,name)
 for _,r in ipairs(rows(p))do
  local label=r.nameButton.text:GetText():gsub('|c%x%x%x%x%x%x%x%x%[Selected%] |r','')
  if label==name or label:sub(1,#name+2)==name..'  ' then return r end
 end
end
-- Names of the visible rows that carry the marker, in list order.
local function marked()
 local p=open();local out={}
 for _,r in ipairs(rows(p))do
  local label=r.nameButton.text:GetText()
  if label:find('[Selected]',1,true)then
   out[#out+1]=label:gsub('|c%x%x%x%x%x%x%x%x%[Selected%] |r',''):gsub('  |c.*$','')
  end
 end
 close()
 return table.concat(out,',')
end
local function saved(context)
 local state=Nexus.Store.State()
 if context==0 then return state.firstRunWishlist end
 return state.loadoutWishlists[context]
end
local function pick(name,context)
 local p=open();local r=assert(row(p,name),'actual picker has '..name)
 r.nameButton:Click()
 check(not p:IsShown() and A.AssignedWishlist().name==name,'clicking '..name..' assigns it')
 check(saved(context).assignmentId,'SETUP: the stored assignment carries an assignmentId')
 check(name:sub(1,5)~='Live ' or (tonumber(saved(context).slot) and saved(context).designRows==nil),
  'SETUP: '..name..' is a plain server row (slot, no local design)')
end
local function server(list)
 for slot=101,110 do H.perks.serverBuildSlots[slot]=nil end
 for slot,r in pairs(list)do
  H.perks.serverBuildSlots[slot]={name=r[1],verified=false,echoes=H.Clone(r[2])}
 end
 H.Notify();A.Poll()
end
local function variant(n)
 local e=H.Clone(rolled);e[1].spellId=e[1].spellId+500+n;return e
end
-- Reading the picker never changes the assignment, saves, spends or acts.
local function expect(context,want,label)
 local before=H.Clone(saved(context))
 local saves,spends=H.Count('save'),H.Count('orb-spend')
 local got=marked()
 print('SELECTED_MARKER',label,'context',context,'marked',got=='' and '-' or got)
 check(got==want,label..': marked "'..want..'", got "'..got..'"')
 check(T.Equal(before,saved(context)),label..': reading the picker keeps the stored assignment')
 check(H.Count('save')==saves and H.Count('orb-spend')==spends and #H.actions==actions,
  label..': reading the picker saves, spends and submits nothing')
end

H.perks.serverBuildSlots[103]={name='Plan C',verified=false,echoes=H.Clone(rolled)}
H.Notify();A.Poll()
for _,slot in ipairs({101,102,103})do
 check(A.WishlistKey(H.perks.serverBuildSlots[slot].echoes)==k,'SETUP: rolled contents are identical')
end
check(H.perks.serverActiveSlot==2,'SETUP: numbered Saved Build is active')

-- 1. A local design plan: both sides carry the same assignmentId.
check(A.AssignedWishlist().name=='Plan B' and saved(2).designRows,'SETUP: Plan B design plan is assigned')
expect(2,'Plan B','design plan (equal assignmentId)')

for _,context in ipairs({2,0})do
 H.perks.serverActiveSlot=context;H.Notify();A.Poll()
 server({[101]={'Live A',rolled},[102]={'Live B',rolled},[103]={'Live C',rolled}})
 -- Live rows get their own names: the fixture also keeps loadout 1's stored
 -- 'Plan A' design plan, which carries another assignmentId and must never be marked.
 -- 2. Plain equal-content server rows: only the clicked slot is marked.
 pick('Live A',context);expect(context,'Live A','Live A of three equal-content rows')
 pick('Live B',context);expect(context,'Live B','equal-content Live B')
 pick('Live C',context);expect(context,'Live C','equal-content Live C')
 -- 3. A normal refresh keeps the marker on the same row.
 H.Notify();A.Poll();Nexus.JournalTab.RefreshAssociations()
 expect(context,'Live C','after a normal refresh')
 -- 4. The assigned slot is gone and exactly one live row has its contents:
 -- the resolver follows it, and the marker shows that current row.
 server({[101]={'Live A',variant(2)},[102]={'Live B',variant(3)},[104]={'Live E',rolled}})
 expect(context,'Live E','unique moved identity')
 -- 5. The assigned slot changed and its contents exist nowhere live. The
 -- changed live row is not marked. The picker keeps offering the retained
 -- assignment itself (its stored copy, same assignmentId): only that is marked.
 server({[101]={'Live A',rolled},[102]={'Live B',rolled},[103]={'Live C',rolled}})
 pick('Live C',context)
 server({[101]={'Live A',variant(2)},[102]={'Live B',variant(3)},[103]={'Live C changed',variant(1)}})
 local retained=0
 for _,c in ipairs(A.GetWishlistCandidates())do
  if c.name=='Live C' then
   retained=retained+1
   check(c.stored and c.key==k and c.assignmentId==saved(context).assignmentId,'SETUP: the Live C row is the retained stored assignment')
  end
 end
 check(retained==1,'SETUP: exactly one retained Live C row')
 expect(context,'Live C','changed assigned slot (live row unmarked, retained assignment marked)')
 -- 6. The assigned slot is gone and two rows have its contents: ambiguous,
 -- so no marker, whether or not a row has the assigned name.
 server({[101]={'Live A',rolled},[102]={'Live B',rolled},[103]={'Live C',rolled}})
 pick('Live C',context)
 server({[105]={'Live D',rolled},[106]={'Live F',rolled}})
 expect(context,'','ambiguous moved identity, other names')
 server({[105]={'Live C',rolled},[106]={'Live C',rolled}})
 expect(context,'','ambiguous moved identity, same name twice')
 -- 7. The assigned slot still exists and two other slots hold equal contents:
 -- key equality in another slot marks nothing.
 server({[101]={'Live A',rolled},[102]={'Live B',rolled},[103]={'Live C',rolled}})
 pick('Live B',context);expect(context,'Live B','assigned slot present among equal keys')
 -- 8. Unassign: no row is marked.
 local p=open();p.clearRow:Click()
 check(A.AssignedWishlist().state=='unassigned','SETUP: Unassign clears the association')
 expect(context,'','after Unassign')
end
check(#H.actions==actions and H.Count('orb-spend')==0,'no gameplay or service mutation in the whole test')
print('PASS picker [Selected] marks exactly the resolved assignment; equal contents elsewhere, names, changed live rows and ambiguous identities mark nothing; checks='..checks)
