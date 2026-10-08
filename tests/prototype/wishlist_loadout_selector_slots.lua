-- Wishlist editor Saved Build selector: the rows are the Saved Builds the server declares (W7).
-- The selector listed Saved Builds 1-5 only, although the server can declare more (GetServerMaxSlots)
-- and the controller, the adapter and the save path already support a declared sixth slot. Required:
-- the selector lists slots 1..maxSlots as declared (5 when nothing is declared or the declaration is
-- not a whole number from 1 up; at most 10 rows); a slot with no readable data is a disabled "Empty"
-- row, nothing is guessed; designed Wishlist mirrors above the declared range are never listed; a row
-- selects by its slot number only (it neither activates a server loadout nor writes an assignment); the
-- five-slot behaviour is unchanged. Real boot, real editor frame, real selector menu rows, controller
-- and adapter; the synthetic server answers GetServerBuildSlots/GetServerMaxSlots/GetServerActiveSlot.
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,A
local E1={{spellId=201172,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local function Boot(o)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;ProjectEbonholdEchoJournal=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201173,'Echo Six',0,5);H.AddEcho(201174,'Echo Free',0,5)
 H.AddEcho(200767,'Echo Lock',0,5)
 H.maxSlotsValue=o.maxSlots
 if o.maxSlots==false then H.service.GetServerMaxSlots=function() return nil end
 else H.service.GetServerMaxSlots=function() return H.maxSlotsValue or 5 end end
 H.perks.serverBuildSlots=o.slots
 H.perks.serverActiveSlot=o.active or 0
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function()error('choosing a Saved Build must not spend')end}
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
end
local function Rows(n)
 local out={}
 for i=1,n do out[i]={name='Saved '..i,verified=true,echoes=H and H.Clone(E1) or E1} end
 return out
end
local function Six()
 return {[1]={name='One',verified=true,echoes=E1},[6]={name='Six',verified=true,echoes=E6},
  [101]={name='W-One',verified=false,echoes=E1},[106]={name='W-Six',verified=false,echoes=E6},
  [107]={name='W-Free',verified=false,echoes=EF}}
end
local function selectorButton()
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and tostring(f:GetText() or ''):find('Saved Build: ',1,true) then return f end
 end
 error('selector button absent')
end
local function menu() for _,f in ipairs(H.frames) do if f:GetName()=='NexusWishlistEditorLoadoutMenu' then return f end end end
local function plain(s) return (tostring(s or ''):gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')) end
-- The visible selector rows, top to bottom.
local function OpenRows()
 local m=menu()
 if m and m:IsShown() then selectorButton():Click() end -- close a menu left open
 selectorButton():Click()
 m=menu();check(m and m:IsShown(),'the selector menu opens')
 local out={}
 for _,r in ipairs(m.rows) do if r:IsVisible() then out[#out+1]=r end end
 return out,m
end
local function Texts(rows) local t={} for i,r in ipairs(rows) do t[i]=plain(r._label:GetText()) end return t end
local function Select(row) assert(row.scripts.OnMouseDown,'a disabled row has no handler');row.scripts.OnMouseDown(row,'LeftButton') end
local function Ctx()
 local show=Nexus.WishlistEditor.Show
 for i=1,255 do local n,v=debug.getupvalue(show,i);if not n then break end
  if n=='wishlistController' then return v.EditingContext() or {},v.CreateTargetContext() or {} end end
 error('editor controller not found')
end
local function Count(t) local n=0 for _ in pairs(t or {}) do n=n+1 end return n end

-- 1. A declared sixth Saved Build (slots 1 and 6 hold builds; designed mirrors sit above the range).
Boot({maxSlots=6,active=6,slots=Six()})
SlashCmdList.NEXUS('editor')
local rows,m=OpenRows()
local text=Texts(rows)
check(#rows==6,'six declared Saved Builds give six rows: '..#rows..' ('..table.concat(text,' | ')..')')
check(text[1]:find('One',1,true) and text[6]:find('Six',1,true),'row 1 is One and row 6 is Six: '..table.concat(text,' | '))
for i=2,5 do check(text[i]:find('Loadout '..i,1,true) and text[i]:find('Empty',1,true) and not rows[i].enabled,
 'slot '..i..' has no data: a disabled Empty row, nothing guessed: '..text[i]) end
check(rows[6].enabled and rows[1].enabled,'the two populated rows are enabled')
for _,t in ipairs(text) do check(not t:find('W-',1,true),'a designed Wishlist mirror is not a Saved Build row: '..t) end
check(m:GetHeight()==18+6*24,'the menu is as tall as its six rows: '..tostring(m:GetHeight()))
local activeColour=rows[6]._label:GetText():sub(1,10)
check(activeColour=='|cffffd200' and rows[1]._label:GetText():sub(1,10)=='|cffffffff','the active server slot (6) is the highlighted one')
local before=H.actions and #H.actions or 0
local storeBefore=Count(Nexus.Store.State().loadoutWishlists)
Select(rows[6])
local ctx,target=Ctx()
check((ctx.loadoutSlot or target.loadoutSlot)==6,'choosing row 6 selects Saved Build 6 (context '..tostring(ctx.loadoutSlot)..' / '..tostring(target.loadoutSlot)..')')
check(not m:IsShown(),'the menu closes after a choice')
rows=OpenRows()
Select(rows[1])
ctx,target=Ctx()
check((ctx.loadoutSlot or target.loadoutSlot)==1,'choosing row 1 selects Saved Build 1')
rows=OpenRows()
Select(rows[6])
ctx,target=Ctx()
check((ctx.loadoutSlot or target.loadoutSlot)==6,'and back to 6: the choice is by slot number, stable across reopening')
check(selectorButton():GetText():find('Six',1,true),'the selector button names Saved Build 6: '..selectorButton():GetText())
check((H.actions and #H.actions or 0)==before,'choosing rows uploaded, activated or saved nothing')
check(Count(Nexus.Store.State().loadoutWishlists)==storeBefore,'choosing rows wrote no assignment')
-- A disabled row does nothing.
rows=OpenRows()
check(rows[3].scripts.OnMouseDown==nil and rows[3].scripts.OnClick==nil,'an Empty row has no handler')

-- 2. Five declared Saved Builds: five rows, as before.
Boot({maxSlots=5,active=1,slots=Rows(5)})
SlashCmdList.NEXUS('editor')
rows,m=OpenRows()
text=Texts(rows)
check(#rows==5 and m:GetHeight()==18+5*24,'five declared Saved Builds give five rows and the old height: '..#rows)
for i=1,5 do check(text[i]:find('Saved '..i,1,true) and rows[i].enabled,'row '..i..' lists its Saved Build') end
check(rows[1]._label:GetText():sub(1,10)=='|cffffd200','the active slot 1 is highlighted')
Select(rows[5]);ctx,target=Ctx()
check((ctx.loadoutSlot or target.loadoutSlot)==5,'choosing row 5 selects Saved Build 5')

-- 3. Nothing declared, or the slot data unreadable: the five old rows; nothing is invented.
Boot({maxSlots=false,active=0,slots=Rows(2)})
SlashCmdList.NEXUS('editor')
rows=OpenRows();text=Texts(rows)
check(#rows==5,'no declaration: five rows: '..#rows)
check(rows[1].enabled and rows[2].enabled and not rows[3].enabled and not rows[4].enabled and not rows[5].enabled,'only the two readable slots are enabled')
Boot({maxSlots=6,active=0,slots=nil})
SlashCmdList.NEXUS('editor')
rows=OpenRows();text=Texts(rows)
-- The declaration is published only with the slot data (Slots() is nil without it), so nothing is known: the old five.
check(#rows==5,'no slot data readable, so no declaration is known: five rows: '..#rows)
for i=1,5 do check(not rows[i].enabled and text[i]:find('Empty',1,true),'unreadable slot '..i..' is a disabled Empty row') end

-- 4. Sparse declaration: slot 6 declared, slot 6 absent.
Boot({maxSlots=6,active=1,slots={[1]={name='One',verified=true,echoes=E1},[101]={name='W-One',verified=false,echoes=E1}}})
SlashCmdList.NEXUS('editor')
rows=OpenRows();text=Texts(rows)
check(#rows==6 and not rows[6].enabled and text[6]:find('Loadout 6',1,true) and text[6]:find('Empty',1,true),'a declared sixth slot without data is a disabled Empty row: '..text[6])
check(rows[1].enabled,'slot 1 stays selectable')

-- 4b. A readable slot 6 with no name keeps the generic label and stays selectable.
Boot({maxSlots=6,active=6,slots={[6]={name='',verified=true,echoes=E6}}})
SlashCmdList.NEXUS('editor')
rows=OpenRows();text=Texts(rows)
check(#rows==6 and rows[6].enabled and text[6]:find('Loadout 6',1,true) and not text[6]:find('Empty',1,true),'an unnamed readable sixth slot is labelled Loadout 6 and enabled: '..text[6])
Select(rows[6]);ctx,target=Ctx()
check((ctx.loadoutSlot or target.loadoutSlot)==6,'and it selects Saved Build 6')

-- 5. Declarations: used as given from 1 up to ten rows; anything else keeps five rows.
local function RowsFor(value)
 Boot({maxSlots=value,active=1,slots=Rows(1)})
 SlashCmdList.NEXUS('editor')
 local r=OpenRows();return #r
end
for declared,expected in pairs({[1]=1,[2]=2,[3]=3,[4]=4,[7]=7,[10]=10,[11]=10,[50]=10,[0]=5,[-3]=5,[2.5]=5,[math.huge]=5}) do
 local got=RowsFor(declared)
 check(got==expected,'declared '..tostring(declared)..' gives '..expected..' rows: '..got)
end
Boot({maxSlots='6',active=1,slots=Rows(1)})
SlashCmdList.NEXUS('editor')
check(#(OpenRows())==6,'a numeric string declaration counts as the number it is')
Boot({maxSlots=0/0,active=1,slots=Rows(1)})
SlashCmdList.NEXUS('editor')
check(#(OpenRows())==5,'a NaN declaration keeps five rows')

-- 6. The declaration changes while the editor is open: the same menu follows it.
Boot({maxSlots=6,active=6,slots=Six()})
SlashCmdList.NEXUS('editor')
rows,m=OpenRows()
check(#rows==6,'six rows while six are declared')
H.maxSlotsValue=5;H.Notify();A.Poll();H.Advance(1)
rows,m=OpenRows()
check(#rows==5 and m:GetHeight()==18+5*24,'declared five again: the sixth row is hidden and the menu shrinks: '..#rows)
H.maxSlotsValue=6;H.Notify();A.Poll();H.Advance(1)
rows=OpenRows()
check(#rows==6 and rows[6].enabled,'declared six again: the sixth row returns and is selectable')

print('PASS wishlist_loadout_selector_slots: declared six, five, none, unreadable, sparse and odd declarations; designed mirrors never listed; choice by slot number only; nothing written or activated checks='..checks)
