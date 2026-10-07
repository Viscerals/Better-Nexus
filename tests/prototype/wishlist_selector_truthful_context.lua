-- F-S4-2 (P3), regression-first: the Wishlist editor's Saved Build selector
-- tells the truth about what choosing a Saved Build does. Choosing a row only
-- selects which Saved Build's Wishlist assignment is edited
-- (WishlistController.SelectLoadout; the server's active Saved Build is not
-- changed), but the selector's tooltip says that it "Activates the selected
-- server Saved Build ... This changes the active loadout." and its label then
-- reads "Active Loadout: <chosen build>" while the server, the adapter and
-- automation still use the other, really active build.
-- Healthy behaviour (EXPECT, fails at the baseline): the selector tooltip
-- promises no activation (no sentence says that it activates a Saved Build or
-- changes, switches or swaps the active one, unless negated), before and after
-- a choice; after choosing the inactive Saved Build "Ardent" while "Vesper" is
-- active, the label does not claim that Ardent is active.
-- Unchanged (GUARD, holds at the baseline): the label names the Saved Build
-- being edited and never claims an inactive one is active; choosing a row
-- activates, saves, uploads, spends or locks nothing; the native and adapter
-- active slot stays Vesper; the Saved Build Wishlist assignments stay as they
-- were (Ardent's W-Ardent and Vesper's W-Vesper, assigned through the adapter
-- before the editor opens); the selector menu closes on a choice; no game
-- action. The label's exact words are not fixed here: existing tests that
-- find the selector by its present "Active Loadout" text are corrected with
-- the implementation, not in this phase.
-- Nexus.WishlistEditor has no Hide: the editor is closed with its public
-- Toggle (/nexus editor), and only while it is shown.
-- Real TOC boot, adapter, controller and editor controls (the selector is
-- found by its structure, not its words). Artificial Saved Builds; the Orb
-- service is a fake that only counts calls; GameTooltip's text methods are
-- observed through view_regression_support V.TooltipLines.
local H=dofile('tests/prototype/harness.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local printable=V.printable
local C=V.Checker('wishlist_selector_truthful_context')
H.playerLevel=80;wipe(H.db)
H.AddEcho(201172,'Artificial Echo Ardent',0,5)
H.AddEcho(201173,'Artificial Echo Vesper',0,5)
H.AddEcho(200767,'Artificial Echo Lock',0,5)
local EA={{spellId=201172,quality=0,stacks=1}}
local EV={{spellId=201173,quality=0,stacks=1}}
H.service.GetServerMaxSlots=function()return 6 end
H.perks.serverBuildSlots={
 [1]={name='Ardent',verified=true,echoes=EA},
 [6]={name='Vesper',verified=true,echoes=EV},
 [101]={name='W-Ardent',verified=false,echoes=EA},
 [106]={name='W-Vesper',verified=false,echoes=EV},
}
H.perks.serverActiveSlot=6
local spends=0
ProjectEbonhold.OrbService={IsStateKnown=function()return true end,
 GetCharges=function()return 0 end,IsOfferPending=function()return false end,
 RequestCharges=function()end,ConfirmSpend=function()spends=spends+1;return false end}
H.Boot();local A=Nexus.GameAdapter;H.Notify();A.Poll();H.Advance(1)
-- Each Saved Build is given its own server Wishlist through the adapter, as
-- wishlist_editor_binding.lua's LoadoutWorld assigns them.
local okArdent,whyArdent=A.SetLoadoutWishlistIdentity(1,'W-Ardent',H.Clone(EA))
local okVesper,whyVesper=A.SetLoadoutWishlistIdentity(6,'W-Vesper',H.Clone(EV))
H.Notify();A.Poll();H.Advance(1)
C.setup(okArdent==true and okVesper==true,'fixture: both Saved Builds are given their Wishlist through the adapter',
 printable(whyArdent)..'/'..printable(whyVesper))

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
local function Hover()
 local button=Selector()
 if not button then return '',0 end
 local lines,ok,err=V.TooltipLines(function() button:GetScript('OnEnter')(button) end)
 C.setup(ok,'fixture: the selector tooltip renders',err)
 return V.Plain(table.concat(lines,'\n')),#lines
end
local function Assignment(slot)
 local linked=A.GetLoadoutWishlist(slot)
 return linked and tostring(linked.name) or 'none'
end
-- The Saved Build Wishlist assignments of Ardent (1) and Vesper (6): each
-- stored record's name, content key and assignment identity (every
-- assignment write stamps a new one), the server Wishlist it resolves to, the
-- number of stored assignments and the first-run plan.
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
local FACTS
-- Choose Saved Build `slot` with the real selector menu row.
local function Choose(tag,slot)
 local button=Selector()
 if not button then return false end
 button:Click()
 local menu=NexusWishlistEditorLoadoutMenu
 local row=menu and menu.rows and menu.rows[slot]
 C.setup(menu~=nil and menu:IsShown() and row~=nil and row:IsEnabled(),tag..': fixture: the real menu offers Saved Build '..slot)
 if not (row and row:GetScript('OnMouseDown')) then return false end
 row:GetScript('OnMouseDown')(row,'LeftButton')
 H.Advance(.6)
 C.guard(not menu:IsShown(),tag..': choosing a row closes the selector menu')
 return true
end
local function Unchanged(tag)
 C.guard(H.perks.serverActiveSlot==6 and A.Slots().activeSlot==6,tag..': the native and adapter active Saved Build stays Vesper',
  printable(H.perks.serverActiveSlot)..'/'..printable(A.Slots().activeSlot))
 C.guard(#H.actions==0 and spends==0,tag..': nothing was activated, saved, uploaded, locked or spent',#H.actions+spends)
 print('OBSERVED',tag,'assignments Ardent='..Assignment(1),'Vesper='..Assignment(6))
 C.guard(Facts()==FACTS,tag..': the Saved Build Wishlist assignments are unchanged',Facts())
end

Nexus.WishlistEditor.Show()
C.setup(NexusEditorFrame~=nil and NexusEditorFrame:IsShown(),'fixture: the Wishlist editor is open')
C.setup(Selector()~=nil,'fixture: the real Saved Build selector is found by its structure')
C.setup(A.Slots().activeSlot==6,'fixture: the adapter reports Vesper as the active Saved Build')
print('OBSERVED','assignments Ardent='..Assignment(1),'Vesper='..Assignment(6))
FACTS=Facts()
local ardent,vesper=A.GetLoadoutWishlist(1),A.GetLoadoutWishlist(6)
C.setup(ardent~=nil and ardent.name=='W-Ardent' and tonumber(ardent.slot)==101
 and vesper~=nil and vesper.name=='W-Vesper' and tonumber(vesper.slot)==106,
 'fixture: Ardent is assigned W-Ardent and Vesper W-Vesper, each its own server Wishlist',FACTS)

C.scenario('S1 the selector before a choice',function()
 local label=Label()
 print('OBSERVED','S1 label='..label)
 C.guard(V.Names(label,'Vesper') and not V.ClaimsActive(label,'Ardent'),
  'S1: the label names the edited Saved Build Vesper and claims no other build active',label)
 local text,n=Hover()
 print('OBSERVED','S1 tooltip='..text:gsub('\n',' / '))
 C.guard(n>0,'S1: the selector has a tooltip',n)
 local promise,sentence=V.ActivationPromise(text)
 C.expect(not promise,'S1: the selector tooltip promises no activation of a Saved Build',sentence)
end)

C.scenario('S2 choosing the inactive Saved Build Ardent',function()
 if not Choose('S2',1) then return end
 local label=Label()
 print('OBSERVED','S2 label='..label)
 C.guard(V.Names(label,'Ardent'),'S2: the label names Ardent, the Saved Build now being edited',label)
 C.expect(not V.ClaimsActive(label,'Ardent'),'S2: the label does not claim that Ardent is the active Saved Build',label)
 local text=Hover()
 local promise,sentence=V.ActivationPromise(text)
 C.expect(not promise,'S2: the selector tooltip still promises no activation',sentence)
 Unchanged('S2')
end)

C.scenario('S3 choosing the active Saved Build Vesper again',function()
 if not Choose('S3',6) then return end
 local label=Label()
 print('OBSERVED','S3 label='..label)
 C.guard(V.Names(label,'Vesper') and not V.ClaimsActive(label,'Ardent'),
  'S3: the label names Vesper and claims no other build active',label)
 Unchanged('S3')
end)

-- Cleanup: the public Toggle closes a shown editor; a closed one is left closed.
C.scenario('cleanup: the public Toggle closes the editor',function()
 if NexusEditorFrame and NexusEditorFrame:IsShown() then Nexus.WishlistEditor.Toggle() end
 C.setup(not (NexusEditorFrame and NexusEditorFrame:IsShown()),'cleanup: the Wishlist editor is closed')
 C.guard(Facts()==FACTS,'the Saved Build Wishlist assignments are unchanged after the editor closed',Facts())
end)
C.guard(#H.actions==0 and spends==0,'no game action and no Orb spend',#H.actions+spends)
C.finish('(the Saved Build selector describes editing, not activation; it changes no server state)')
