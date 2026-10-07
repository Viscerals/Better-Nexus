-- Spec review SPEC-R2-2 (P3), regression-first: the Wishlist editor's Saved
-- Build selector must not name the active Saved Build while the editor edits a
-- Wishlist that no Saved Build has.
-- The editor's Wishlist switch menu ("Editing: ...") labels a Wishlist that no
-- Saved Build has "Saved Build: None" and opens it with no Saved Build
-- (WishlistController BeginWishlist: no loadout slot, no destination), so the
-- context line under the editor's title reads "Saved Build: None" and a save
-- assigns the Wishlist to nothing. The selector's label (WishlistRenderer
-- RefreshView) falls back to the active slot when the editing context has no
-- Saved Build, so it reads "Saved Build: Vesper (active)", and its tooltip says
-- it chooses whose assigned Wishlist this editor shows and edits.
-- Healthy behaviour (EXPECT, fails at 067d6ab): with Vesper active, after the
-- unassigned Wishlist "Free plan" is opened from its switch menu row, and again
-- after its real save, the selector does not present Vesper as the Saved Build
-- whose Wishlist the editor edits (a label may name Vesper only beside a
-- statement that the edited Wishlist has no Saved Build).
-- Unchanged (GUARD, holds at 067d6ab): the context line says the edited
-- Wishlist has no Saved Build and names neither Saved Build; the selector names
-- no other Saved Build and its tooltip promises no activation; the real save
-- confirms an update of Free plan that promises no assignment, uploads only
-- Free plan's own server Wishlist, assigns it to nothing (its switch menu row
-- still says so) and changes neither Saved Build's assignment nor the first-run
-- plan; an assigned Wishlist opened from the same switch menu (Amber plan) and
-- the Saved Builds chosen with the selector (Vesper, Ardent) still name their
-- own Saved Build; the native and adapter active Saved Build stays Vesper;
-- nothing is activated, locked or spent; each menu closes on a choice and with
-- the editor.
-- SETUP: the fixture reached its state (a SETUP failure is not red evidence).
-- Real TOC boot, adapter, controller and editor controls: the switch button and
-- its menu rows, the selector (found by its structure, not its words) and its
-- menu rows, the Echo row's + control, Save Wishlist and its confirmation.
-- Nothing is set on the editor's state directly. Nexus.WishlistEditor has no
-- Hide: the editor is closed with its public Toggle, only while it is shown.
-- Artificial Saved Builds and server Wishlists; the Orb service is a fake that
-- only counts calls; GameTooltip's text methods are observed through
-- view_regression_support V.TooltipLines.
local H=dofile('tests/prototype/harness.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('wishlist_unassigned_selector_context')
H.playerLevel=80;wipe(H.db)
H.AddEcho(201172,'Artificial Echo Ardent',0,5)
H.AddEcho(201173,'Artificial Echo Vesper',0,5)
H.AddEcho(201174,'Artificial Echo Free',0,5)
H.AddEcho(200767,'Artificial Echo Lock',0,5)
local EA={{spellId=201172,quality=0,stacks=1}}
local EV={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
H.service.GetServerMaxSlots=function()return 6 end
H.perks.serverBuildSlots={
 [1]={name='Ardent',verified=true,echoes=EA},
 [6]={name='Vesper',verified=true,echoes=EV},
 [101]={name='Amber plan',verified=false,echoes=EA},
 [106]={name='Violet plan',verified=false,echoes=EV},
 [107]={name='Free plan',verified=false,echoes=EF},
}
H.perks.serverActiveSlot=6
local spends=0
ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
 GetCharges=function()return 0 end,IsOfferPending=function()return false end,
 RequestCharges=function()end,ConfirmSpend=function()spends=spends+1;return false end}
H.Boot();local A=Nexus.GameAdapter;H.Notify();A.Poll();H.Advance(1)
-- Ardent and Vesper are each given their own server Wishlist through the
-- adapter; Free plan is given to no Saved Build.
local okArdent,whyArdent=A.SetLoadoutWishlistIdentity(1,'Amber plan',H.Clone(EA))
local okVesper,whyVesper=A.SetLoadoutWishlistIdentity(6,'Violet plan',H.Clone(EV))
H.Notify();A.Poll();H.Advance(1)
C.setup(okArdent==true and okVesper==true,'fixture: both Saved Builds are given their Wishlist through the adapter',
 printable(whyArdent)..'/'..printable(whyVesper))

-- The Saved Build selector: the editor's selector-styled button that is not
-- the Wishlist switch button.
local function Selector()
 return V.Frame(H,function(f)
  return f.kind=='Button' and f:GetParent()==NexusEditorFrame and f._arrow~=nil
   and f~=NexusWishlistEditorSwitchButton
 end)
end
local function Label()
 local button=Selector()
 return button and V.Plain(button:GetText()) or ''
end
-- The editor's context line: the text the editor anchors directly under its
-- title (found by that anchor, not by its words).
local function ContextLine()
 for _,r in ipairs(NexusEditorFrame and NexusEditorFrame.regions or {}) do
  local at=r.points and r.points[1]
  if r.kind=='FontString' and at and at[1]=='TOP' and type(at[2])=='table'
   and at[2].kind=='FontString' and at[3]=='BOTTOM' then
   return V.Plain(r:GetText() or '')
  end
 end
 return ''
end
local function Hover(tag)
 local button=Selector()
 if not button then return '',0 end
 local lines,ok,err=V.TooltipLines(function() button:GetScript('OnEnter')(button) end)
 C.setup(ok,tag..': fixture: the selector tooltip renders',err)
 return V.Plain(table.concat(lines,'\n')),#lines
end

-- Does the text say that the edited Wishlist has no Saved Build?
local function SaysNoBuild(text)
 local l=V.Plain(text):lower()
 return l:find('saved build:%s*none')~=nil or l:find('no saved build',1,true)~=nil
  or l:find('not assigned',1,true)~=nil or l:find('unassigned',1,true)~=nil
end
-- Does the label present Saved Build `name` as the one whose Wishlist the
-- editor edits? It names that build and does not say that the edited Wishlist
-- has none (a label naming the active build beside such a statement does not).
local function Presents(label,name)
 return V.Names(label,name) and not SaysNoBuild(label)
end

-- The Saved Build Wishlist assignments of Ardent (1) and Vesper (6): each
-- stored record's name, content key and assignment identity, the server
-- Wishlist it resolves to, the number of stored assignments and the first-run
-- plan.
local function Facts()
 local state=Nexus.Store.State() or {}
 local links=type(state.loadoutWishlists)=='table' and state.loadoutWishlists or {}
 local out={}
 for _,slot in ipairs({1,6}) do
  local stored=type(links[slot])=='table' and links[slot] or {}
  local linked=A.GetLoadoutWishlist(slot) or {}
  out[#out+1]=table.concat({slot,printable(stored.name),printable(stored.key),printable(stored.assignmentId),
   printable(linked.name),printable(linked.slot)},'/')
 end
 local first=state.firstRunWishlist
 out[#out+1]='stored='..V.Count(links)..' first='..printable(type(first)=='table' and first.name or first)
 return table.concat(out,' ')
end
-- Every game action so far, as kind/slot/name.
local function Actions()
 local out={}
 for _,a in ipairs(H.actions) do
  out[#out+1]=table.concat({printable(a[1]),printable(a[2]),printable(a[3])},'/')
 end
 return table.concat(out,' ')
end
-- The one action the real save of Free plan makes: the upload of its own
-- server Wishlist (slot 107). No action is expected before that save.
local SAVE_ACTION='upload/107/Free plan'
local expectedActions=''
local FACTS
local function Unchanged(tag)
 C.guard(H.perks.serverActiveSlot==6 and A.Slots().activeSlot==6,tag..': the native and adapter active Saved Build stays Vesper',
  printable(H.perks.serverActiveSlot)..'/'..printable(A.Slots().activeSlot))
 C.guard(Actions()==expectedActions and spends==0,
  tag..': nothing was activated, saved, locked or spent; nothing but the save of Free plan was uploaded',Actions())
 C.guard(Facts()==FACTS,tag..': the Saved Build Wishlist assignments are unchanged',Facts())
end

-- The Wishlist switch menu, opened with its real button; the row of `name`.
local function SwitchRow(tag,name)
 local menu=NexusWishlistEditorSwitchMenu
 if not (menu and menu:IsShown()) then NexusWishlistEditorSwitchButton:Click() end
 menu=NexusWishlistEditorSwitchMenu
 local found
 for _,row in ipairs(menu and menu.rows or {}) do
  if row:IsShown() and row._label and V.Plain(row._label:GetText()):find(name,1,true)==1 then found=row end
 end
 C.setup(menu~=nil and menu:IsShown() and found~=nil and found:IsEnabled(),tag..': fixture: the Wishlist switch menu offers '..name)
 return found
end
-- Choose a row of the switch menu as the player does.
local function ChooseRow(tag,row)
 row:Click()
 H.Advance(.6)
 C.guard(not NexusWishlistEditorSwitchMenu:IsShown(),tag..': choosing the row closes the switch menu')
end
-- Choose Saved Build `slot` with the real selector menu row.
local function Choose(tag,slot)
 local button=Selector()
 if not button then return false end
 button:Click()
 local menu=NexusWishlistEditorLoadoutMenu
 local row=menu and menu.rows and menu.rows[slot]
 C.setup(menu~=nil and menu:IsShown() and row~=nil and row:IsEnabled(),tag..': fixture: the real selector menu offers Saved Build '..slot)
 if not (row and row:GetScript('OnMouseDown')) then return false end
 row:GetScript('OnMouseDown')(row,'LeftButton')
 H.Advance(.6)
 C.guard(not menu:IsShown(),tag..': choosing a row closes the selector menu')
 return true
end
-- The visible editor control `text`, and the + control of the listed Echo `id`.
local function Button(text)
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end
 end
end
local function PlusRow(id)
 for _,f in ipairs(H.frames) do
  if f:IsVisible() and f.plus and f.data and f.data.spellId==id then return f end
 end
end

Nexus.WishlistEditor.Show()
C.setup(NexusEditorFrame~=nil and NexusEditorFrame:IsShown(),'fixture: the Wishlist editor is open')
C.setup(Selector()~=nil,'fixture: the real Saved Build selector is found by its structure')
C.setup(ContextLine()~='','fixture: the editor context line is found under its title')
C.setup(NexusWishlistEditorSwitchButton~=nil,'fixture: the editor has its Wishlist switch button')
C.setup(A.Slots().activeSlot==6,'fixture: the adapter reports Vesper as the active Saved Build')
FACTS=Facts()
print('OBSERVED','assignments '..FACTS)
local ardent,vesper=A.GetLoadoutWishlist(1),A.GetLoadoutWishlist(6)
C.setup(ardent~=nil and ardent.name=='Amber plan' and tonumber(ardent.slot)==101
 and vesper~=nil and vesper.name=='Violet plan' and tonumber(vesper.slot)==106,
 'fixture: Ardent is assigned Amber plan and Vesper Violet plan, each its own server Wishlist',FACTS)

C.scenario('C0 the editor opens on the active Saved Build Vesper',function()
 local line,label=ContextLine(),Label()
 print('OBSERVED','C0 context='..line,'label='..label)
 C.guard(V.Names(line,'Violet plan') and V.Names(line,'Vesper') and not SaysNoBuild(line),
  'C0: the context line names Violet plan and its Saved Build Vesper',line)
 C.guard(Presents(label,'Vesper') and not V.Names(label,'Ardent'),'C0: the selector names Vesper, the Saved Build being edited',label)
end)

C.scenario('U1 the unassigned Free plan, opened from its switch menu row',function()
 local row=SwitchRow('U1','Free plan')
 if not row then return end
 local text=V.Plain(row._label:GetText())
 print('OBSERVED','U1 switch row='..text)
 C.setup(SaysNoBuild(text) and not V.Names(text,'Vesper') and not V.Names(text,'Ardent'),
  'U1: fixture: the switch menu row says Free plan has no Saved Build',text)
 ChooseRow('U1',row)
 local line,label=ContextLine(),Label()
 print('OBSERVED','U1 context='..line,'label='..label)
 C.setup(V.Names(line,'Free plan'),'U1: fixture: the editor now edits Free plan',line)
 C.guard(SaysNoBuild(line) and not V.Names(line,'Vesper') and not V.Names(line,'Ardent'),
  'U1: the context line says the edited Wishlist has no Saved Build and names neither Saved Build',line)
 C.expect(not Presents(label,'Vesper'),
  'U1: the selector does not present the active Saved Build Vesper as the one whose Wishlist is edited',label)
 C.guard(not Presents(label,'Ardent'),'U1: nor Ardent',label)
 local tip,n=Hover('U1')
 print('OBSERVED','U1 tooltip='..tip:gsub('\n',' / '))
 local promise,sentence=V.ActivationPromise(tip)
 C.guard(n>0 and not promise,'U1: the selector tooltip promises no activation',sentence or n)
 Unchanged('U1')
end)

C.scenario('U2 the real save of Free plan',function()
 C.setup(V.Names(ContextLine(),'Free plan'),'U2: fixture: the editor still edits Free plan',ContextLine())
 local row=PlusRow(201174)
 C.setup(row~=nil and row.plus:IsEnabled(),'U2: fixture: Free plan\'s Echo is listed with its + control')
 if not row then return end
 row.plus:Click()
 local save=Button('Save Wishlist')
 C.setup(save~=nil and save:IsEnabled(),'U2: fixture: the editor offers Save Wishlist')
 if not save then return end
 H.popup=nil
 save:Click()
 local popup=H.popup
 C.setup(popup~=nil,'U2: fixture: Save Wishlist asks for confirmation')
 if not popup then return end
 local dialog=StaticPopupDialogs[popup.which] or {}
 local formatted,asked=pcall(string.format,tostring(dialog.text or ''),popup.arg1,popup.arg2)
 asked=V.Plain(formatted and asked or tostring(dialog.text or ''))
 print('OBSERVED','U2 confirmation='..printable(popup.which),'text='..asked:gsub('\n',' / '))
 C.guard(popup.which=='WISHLISTREALIZER_UPDATE_WISHLIST' and V.Names(asked,'Free plan'),
  'U2: the confirmation updates Free plan',popup.which)
 C.guard(asked:lower():find('assign',1,true)==nil and not V.Names(asked,'Vesper'),
  'U2: and promises no assignment, to Vesper or to any Saved Build',asked)
 H.AcceptPopup()
 local uploads={}
 for _,a in ipairs(H.actions) do if a[1]=='upload' then uploads[#uploads+1]=a end end
 local last=uploads[#uploads]
 C.setup(last~=nil and last[2]==107 and last[3]=='Free plan','U2: fixture: the save uploaded Free plan to its own server Wishlist',Actions())
 if not last then return end
 expectedActions=SAVE_ACTION
 -- The server's copy of that upload (as wishlist_save_slot_safety mirrors it).
 local rows=H.Clone(H.perks.serverBuildSlots or {})
 rows[107]={name='Free plan',verified=false,echoes=H.Clone(last[4])}
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll();H.Advance(4)
 local line,label=ContextLine(),Label()
 print('OBSERVED','U2 after the save context='..line,'label='..label)
 C.guard(Facts()==FACTS,'U2: the save changes neither Saved Build assignment nor the first-run plan',Facts())
 local nowArdent,nowVesper=A.GetLoadoutWishlist(1),A.GetLoadoutWishlist(6)
 C.guard(nowVesper~=nil and nowVesper.name=='Violet plan' and nowArdent~=nil and nowArdent.name=='Amber plan',
  'U2: Vesper still has Violet plan and Ardent Amber plan',printable(nowVesper and nowVesper.name)..'/'..printable(nowArdent and nowArdent.name))
 C.guard(V.Names(line,'Free plan') and SaysNoBuild(line) and not V.Names(line,'Vesper'),
  'U2: the context line still says the edited Free plan has no Saved Build',line)
 C.expect(not Presents(label,'Vesper'),
  'U2: after the save, the selector still does not present Vesper as the Saved Build being edited',label)
 local again=SwitchRow('U2','Free plan')
 local text=again and V.Plain(again._label:GetText()) or ''
 print('OBSERVED','U2 switch row after the save='..text)
 C.guard(again~=nil and SaysNoBuild(text) and not V.Names(text,'Vesper'),
  'U2: its switch menu row still says Free plan has no Saved Build: the save assigned it to nothing',text)
 NexusWishlistEditorSwitchButton:Click()
 C.guard(not NexusWishlistEditorSwitchMenu:IsShown(),'U2: the switch button closes its menu again')
 Unchanged('U2')
end)

C.scenario('C1 the assigned Amber plan, opened from the same switch menu',function()
 local row=SwitchRow('C1','Amber plan')
 if not row then return end
 local text=V.Plain(row._label:GetText())
 C.setup(V.Names(text,'Ardent'),'C1: fixture: the switch menu row names its Saved Build Ardent',text)
 ChooseRow('C1',row)
 local line,label=ContextLine(),Label()
 print('OBSERVED','C1 context='..line,'label='..label)
 C.guard(V.Names(line,'Amber plan') and V.Names(line,'Ardent') and not SaysNoBuild(line),
  'C1: the context line names Amber plan and its Saved Build Ardent',line)
 C.guard(Presents(label,'Ardent') and not V.ClaimsActive(label,'Ardent') and not V.Names(label,'Vesper'),
  'C1: the selector names Ardent, the Saved Build being edited, and does not claim it is active',label)
 Unchanged('C1')
end)

C.scenario('C2 the Saved Builds chosen with the selector',function()
 if Choose('C2 Vesper',6) then
  local line,label=ContextLine(),Label()
  print('OBSERVED','C2 Vesper context='..line,'label='..label)
  C.guard(V.Names(line,'Violet plan') and V.Names(line,'Vesper'),'C2 Vesper: the editor edits Vesper\'s Violet plan',line)
  C.guard(Presents(label,'Vesper') and not V.Names(label,'Ardent'),'C2 Vesper: and the selector names Vesper',label)
  Unchanged('C2 Vesper')
 end
 if Choose('C2 Ardent',1) then
  local line,label=ContextLine(),Label()
  print('OBSERVED','C2 Ardent context='..line,'label='..label)
  C.guard(V.Names(line,'Amber plan') and V.Names(line,'Ardent'),'C2 Ardent: the editor edits Ardent\'s Amber plan',line)
  C.guard(Presents(label,'Ardent') and not V.ClaimsActive(label,'Ardent'),
   'C2 Ardent: and the selector names Ardent without claiming it is active',label)
  Unchanged('C2 Ardent')
 end
end)

-- Cleanup: the public Toggle closes a shown editor; a closed one is left closed.
C.scenario('cleanup: the editor closes with its menus',function()
 if NexusEditorFrame and NexusEditorFrame:IsShown() then
  NexusWishlistEditorSwitchButton:Click()
  C.setup(NexusWishlistEditorSwitchMenu~=nil and NexusWishlistEditorSwitchMenu:IsShown(),
   'cleanup: fixture: the switch menu is open when the editor closes')
  Nexus.WishlistEditor.Toggle()
 end
 C.setup(not (NexusEditorFrame and NexusEditorFrame:IsShown()),'cleanup: the Wishlist editor is closed')
 C.guard(not (NexusWishlistEditorSwitchMenu and NexusWishlistEditorSwitchMenu:IsShown())
  and not (NexusWishlistEditorLoadoutMenu and NexusWishlistEditorLoadoutMenu:IsShown()),
  'cleanup: closing the editor closes its switch and selector menus')
 C.guard(Facts()==FACTS,'cleanup: the Saved Build Wishlist assignments are unchanged after the editor closed',Facts())
end)
C.guard(Actions()==expectedActions and spends==0,'no other game action and no Orb spend: the only action is the save of Free plan',Actions())
C.finish('(an editor on a Wishlist with no Saved Build does not present the active one; the save assigns nothing)')
