-- M4 (UX-04 / LP-04 foundation): the Nexus panel names the destination its
-- run belongs to, from facts the shown model already carries, and tells the
-- states apart: an active named Saved Build, the first-run target (no Saved
-- Build in use), an empty Saved Build, an unassigned one and an unavailable
-- assignment, and it names the character. Without a verified active row it
-- claims neither first-run nor an active Saved Build (a kept Saved Build, a
-- payload without the verified field) and says a restoring assignment is not
-- known yet (D10-D12). Long and multibyte names are shown
-- whole; a generated copy name is cut only at a whole 3- or 4-byte letter
-- (PRIORITY.N9, D8). A captured editor
-- destination is never replaced by a newly active Saved Build (J3), and the
-- Journal assignment readback, the empty-Saved-Build refusal and the
-- no-second-upload rule stay as they are (J2). Reading any of this writes,
-- sends, requests and activates nothing.
-- Categories (view_regression_support): EXPECT is behaviour added in M4 (it
-- fails on the accepted M3 cut ab3cb307); GUARD already holds there and must
-- keep holding; SETUP is the fixture. Oracles: the tooltip the real panel
-- button shows (its own OnEnter handler), the editor's own context, the Journal
-- selector, game-action/send/request counters and counted assignment writers.
-- Real TOC boot, adapter, runtime, panel, editor and Journal chooser;
-- synthetic host services only. No native claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_destination_context')
local H,A,writes
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
-- 2- and 4-byte UTF-8 letters, longer than any header field.
local LONG='Feuerpr\195\188fung \195\156berl\195\164nge \240\159\148\165 '..string.rep('lange Bezeichnung ',4)
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}

local function World(extra)
 local slots={[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [3]={name='Empty three',verified=true,echoes={}},[6]={name='Six',verified=true,echoes=E6},
  [106]={name='W-Six',verified=false,echoes=E6},[107]={name='W-Free',verified=false,echoes=EF}}
 for k,v in pairs(extra or {}) do slots[k]=v end
 return slots
end
local function Boot(active,slots)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;EchoJournalMicroButton=nil
 NexusEditorFrame=nil;NexusWishlistNameInput=nil;NexusWishlistEditorSwitchButton=nil
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusWishlistAssignNowButton=nil
 NexusWishlistEditorLoadoutMenu=nil;NexusWishlistSaveOnlyButton=nil;NexusPanel=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201173,'Echo Six',0,5);H.AddEcho(201174,'Echo Free',0,5)
 H.AddEcho(201175,'Echo Fire',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots=H.Clone(slots or World())
 H.perks.serverActiveSlot=active
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function() error('viewing a destination must not spend') end}
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
 writes={}
 for _,k in ipairs(WRITERS) do
  local real=A[k]
  if type(real)=='function' then
   writes[k]=0
   A[k]=function(...) writes[k]=writes[k]+1;return real(...) end
  end
 end
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
end
local function Zero() for k in pairs(writes) do writes[k]=0 end end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
-- Everything a passive view must leave alone.
local function Effects()
 local uploads,others=0,0
 for _,a in ipairs(H.actions) do if a[1]=='upload' then uploads=uploads+1 else others=others+1 end end
 return {writes=Writes(),uploads=uploads,others=others,sent=#H.sent,granted=tonumber(H.grantedRequests) or 0,auto=Auto()}
end
local function Same(a,b)
 return a.writes==b.writes and a.uploads==b.uploads and a.others==b.others and a.sent==b.sent
  and a.granted==b.granted and a.auto==b.auto
end
local function Describe(e) return 'writes='..e.writes..' uploads='..e.uploads..' actions='..e.others..' sent='..e.sent..' granted='..e.granted end
-- The HUD model the real runtime publishes for the current state.
local function Refresh()
 Nexus.Panel.Show()
 if Nexus.RequestRecompute then Nexus.RequestRecompute() end
 H.Notify();A.Poll();H.Advance(1)
 return Nexus.Panel._lastModel
end
-- The tooltip of the panel's My Builds button, through its own OnEnter.
local function HeaderTip()
 local frame=NexusPanel
 local button=frame and frame._switchBtn
 if not (button and button:GetScript('OnEnter')) then return '' end
 local lines=V.TooltipLines(function() button:GetScript('OnEnter')(button) end)
 return V.Plain(table.concat(lines,'\n'))
end
local function Ctrl()
 local show=Nexus.WishlistEditor.Show
 for i=1,255 do local n,v=debug.getupvalue(show,i);if not n then break end
  if n=='wishlistController' then return v end end
 error('editor controller not found')
end
local function Has(text,needle) return text:find(needle,1,true)~=nil end

C.scenario('D1 an active named Saved Build and its assigned Wishlist are named',function()
 Boot(2)
 C.setup(A.SetLoadoutWishlist(2,107)==true,'D1: fixture: Saved Build 2 (Fire PvE) is assigned W-Free')
 local model=Refresh()
 C.setup(type(model)=='table' and type(model.progress)=='table','D1: fixture: the runtime published a panel model')
 Zero()
 local before=Effects()
 local tip=HeaderTip()
 print('OBSERVED','D1 tip='..tip)
 C.guard(Has(tip,'Open My Builds'),'D1: the button keeps its own title',tip)
 C.expect(Has(tip,"Saved Build 'Fire PvE' (slot 2)") and Has(tip,'active in the game'),
  'D1: it names the active Saved Build by name and slot',tip)
 C.expect(Has(tip,'W-Free (assigned)'),'D1: and the Wishlist assigned to it',tip)
 -- J3 step 5: the destination names its character (the harness player).
 C.expect(Has(tip,'Character: PrototypeTester'),'D1: and the character the run belongs to',tip)
 C.guard(Same(Effects(),before),'D1: hovering writes, uploads, sends, requests and activates nothing',Describe(Effects()))
end)

C.scenario('D2 the first-run target is not a Saved Build',function()
 Boot(0,{[107]={name='W-Free',verified=false,echoes=EF}})
 C.setup(A.SetFirstRunWishlist(107)==true,'D2: fixture: W-Free is the first-run target; no Saved Build is active')
 Refresh()
 local before=Effects()
 local tip=HeaderTip()
 print('OBSERVED','D2 tip='..tip)
 C.expect(Has(tip,'first-run target (no Saved Build in use)'),'D2: the destination is the first-run target',tip)
 C.guard(not Has(tip,"Saved Build '"),'D2: no Saved Build is named as the destination',tip)
 C.guard(Same(Effects(),before),'D2: hovering changes nothing',Describe(Effects()))
end)

C.scenario('D3 an empty Saved Build is empty, not unassigned or missing',function()
 Boot(3)
 local model=Refresh()
 local assignment=type(model)=='table' and model.assignment or {}
 C.setup(assignment.emptySlot==true,'D3: fixture: the active Saved Build 3 holds no Echoes',tostring(assignment.state))
 local tip=HeaderTip()
 print('OBSERVED','D3 tip='..tip)
 C.expect(Has(tip,'empty: it holds no Echoes') and not Has(tip,'none assigned') and not Has(tip,'none captured'),
  'D3: the destination is an empty Saved Build, not an unassigned or missing one',tip)
end)

C.scenario('D4 an unassigned Saved Build and an unavailable assignment are told apart',function()
 Boot(1)
 local model=Refresh()
 local assignment=type(model)=='table' and model.assignment or {}
 C.setup(assignment.state=='unassigned','D4: fixture: Saved Build 1 has no assignment',tostring(assignment.state))
 local tip=HeaderTip()
 print('OBSERVED','D4 unassigned tip='..tip)
 C.expect(Has(tip,"Saved Build 'One' (slot 1)") and Has(tip,'Wishlist: none assigned'),
  'D4: an unassigned Saved Build says no Wishlist is assigned',tip)
 -- The same render path with an unavailable assignment (the model the
 -- runtime publishes while a saved assignment cannot be resolved).
 local unavailable=H.Clone(model)
 unavailable.assignment={state='unavailable',name='Lost plan',activeSlot=1}
 C.setup(Nexus.Panel.Render(unavailable)==true,'D4: fixture: the panel renders the unavailable state')
 tip=HeaderTip()
 print('OBSERVED','D4 unavailable tip='..tip)
 C.expect(Has(tip,'Lost plan - unavailable right now') and not Has(tip,'none assigned'),
  'D4: an unavailable assignment is not shown as unassigned',tip)
end)

C.scenario('D5 a long multibyte Saved Build name is shown whole',function()
 Boot(2,World({[2]={name=LONG,verified=true,echoes=E2}}))
 C.setup(A.SetLoadoutWishlist(2,107)==true,'D5: fixture: the long-named Saved Build 2 is assigned W-Free')
 Refresh()
 local tip=HeaderTip()
 print('OBSERVED','D5 tip='..tip)
 C.expect(Has(tip,"Saved Build '"..LONG.."' (slot 2)"),'D5: the whole name, every multibyte letter intact',tip)
end)

C.scenario('D6 J3: an editor captured for Saved Build 6 is not redirected when another becomes active',function()
 Boot(6)
 C.setup(A.SetLoadoutWishlist(6,106)==true,'D6: fixture: Saved Build 6 is assigned W-Six')
 H.Notify();A.Poll();H.Advance(1)
 for _,cand in ipairs(A.GetWishlistCandidates()) do if cand.slot==106 then Nexus.WishlistEditor.OpenForWishlist(cand,6) end end
 local ctx=Ctrl().EditingContext() or {}
 C.setup(ctx.name=='W-Six' and ctx.loadoutSlot==6,'D6: fixture: W-Six is open for Saved Build 6',ctx.name)
 Zero()
 local before=Effects()
 H.perks.serverActiveSlot=1;H.Notify();A.Poll();H.Advance(1)
 Refresh()
 ctx=Ctrl().EditingContext() or {}
 local tip=HeaderTip()
 print('OBSERVED','D6 editor slot='..tostring(ctx.loadoutSlot)..' tip='..tip)
 C.guard(ctx.name=='W-Six' and ctx.loadoutSlot==6,'D6: the editor keeps its captured Saved Build 6',tostring(ctx.loadoutSlot))
 local after=Effects()
 C.guard(after.writes==before.writes and after.uploads==before.uploads and after.others==before.others
  and after.auto==before.auto,'D6: nothing was activated, written or uploaded; Auto is unchanged',Describe(after))
 C.expect(Has(tip,"Saved Build 'One' (slot 1)"),'D6: the panel names the Saved Build its live run now belongs to',tip)
end)

-- The Echo Journal's Wishlist chooser (real frames, as the player opens it).
local function OpenPicker()
 local journal=_G.ProjectEbonholdEchoJournal or CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
 journal:Show();Nexus.JournalTab.RefreshAssociations()
 local selector=_G.NexusActiveWishlistSelector
 if selector and selector:IsVisible() and not (_G.NexusWishlistOnlyPicker and NexusWishlistOnlyPicker:IsShown()) then
  selector:Click()
 end
 return _G.NexusWishlistOnlyPicker~=nil and NexusWishlistOnlyPicker:IsShown()
end
local function PickerRow(name)
 local picker=_G.NexusWishlistOnlyPicker
 for _,row in ipairs(picker and picker.children or {}) do
  if row.nameButton and row:IsVisible() and V.Plain(tostring(row.nameButton.text:GetText() or '')):find(name,1,true) then return row end
 end
 return nil
end
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return V.Plain(table.concat(heard,' / '))
end

C.scenario('D7 J2: a named assignment reads back; an empty Saved Build is refused; nothing is uploaded',function()
 Boot(2)
 C.setup(not Auto() and OpenPicker(),'D7: fixture: Auto is OFF and the chooser is open for Saved Build 2')
 local row=PickerRow('W-Free')
 C.setup(row~=nil,'D7: fixture: the chooser lists W-Free')
 Zero()
 local before=Effects()
 if row then row.nameButton:Click() end
 Nexus.JournalTab.RefreshAssociations()
 local selector=_G.NexusActiveWishlistSelector
 local readback=selector and selector.text and V.Plain(selector.text:GetText() or '') or ''
 C.guard(writes.SetLoadoutWishlist==1 and readback:find('W-Free',1,true)~=nil,
  'D7: one assignment, read back by the selector',readback)
 C.guard(Effects().uploads==before.uploads,'D7: assigning uploads nothing (no second upload)')
 -- An empty numbered Saved Build: the assignment itself refuses.
 Boot(3)
 C.setup(OpenPicker(),'D7: fixture: the chooser is open for the empty Saved Build 3')
 row=PickerRow('W-Free')
 local said=row and Heard(function() row.nameButton:Click() end) or ''
 C.guard(A.GetLoadoutWishlist(3)==nil and Effects().uploads==0 and said:find('empty or unavailable',1,true)~=nil,
  'D7: the empty Saved Build is refused with its existing reason; nothing is assigned or uploaded',said)
end)

-- PRIORITY.N9 (its M4 UTF-8 portion): a generated copy name is cut at the
-- 120-byte limit only at a whole UTF-8 letter, also for 3- and 4-byte letters
-- and wherever the cap falls (on a boundary, or after 1, 2 or 3 bytes of a
-- letter). The rule is the model's own WishlistModel UniqueName, the function
-- a Create with a taken name uses (WishlistController DraftModel.UniqueName);
-- D5 keeps the whole-name display. No server name limit is assumed. This
-- already holds on the accepted M3 cut: a GUARD (positive control), not a new
-- behaviour.
local THREE,FOUR='\226\130\172','\240\159\148\165' -- euro sign, fire
C.scenario('D8 PRIORITY.N9: copy names are cut at whole 3- and 4-byte letters at the 120-byte limit',function()
 Boot(2)
 local factory=Nexus.WishlistModel
 local model=factory and factory.New and factory.New()
 local unique,key=model and model.UniqueName,model and model.NameKey
 local valid=Nexus.Identity and Nexus.Identity.ValidUtf8
 C.setup(type(unique)=='function' and type(key)=='function' and type(valid)=='function',
  'D8: fixture: the model publishes its copy-name rule')
 if type(unique)~='function' or type(key)~='function' or type(valid)~='function' then return end
 local suffix=' (Copy 1)'
 local room=120-#suffix
 local bad,cases={},0
 for _,letter in ipairs({THREE,FOUR}) do
  local w=#letter
  for lead=0,3 do
   local ascii=string.rep('A',lead)
   local base=ascii..string.rep(letter,math.ceil(120/w)+1)
   local got=unique(base,{[key(base)]=true})
   -- Independent expectation: the ASCII lead, then as many whole letters
   -- as fit in the bytes left for the name before its suffix.
   local want=ascii..string.rep(letter,math.floor((room-lead)/w))..suffix
   cases=cases+1
   if got~=want or #got>120 or not valid(got) then
    bad[#bad+1]=w..'-byte, lead '..lead..': '..tostring(got and #got)..' bytes'
   end
  end
 end
 print('OBSERVED','D8 cut cases='..cases..' mismatches='..#bad)
 C.guard(cases==8 and #bad==0,
  'D8: every generated copy name keeps whole 3- and 4-byte letters, ends with its suffix and fits 120 bytes',table.concat(bad,'; '))
end)

-- D9 (UX-04/UX-15, final copy closure): the editor's Saved Build selector
-- names an unnamed Saved Build and a declared slot with no data "Saved Build N",
-- the one term the destination uses, not "Loadout N". The row count, menu
-- height, selection by slot, enabled/Empty state and no-effect behaviour are
-- unchanged (wishlist_loadout_selector_slots keeps every predicate). Real
-- editor frame, real selector menu rows and handlers.
local function SelectorRows()
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and tostring(f:GetText() or ''):find('Saved Build: ',1,true) then f:Click();break end
 end
 local menu=_G.NexusWishlistEditorLoadoutMenu
 local rows={}
 for _,r in ipairs(menu and menu.rows or {}) do if r:IsVisible() then rows[#rows+1]=r end end
 return rows,menu
end
C.scenario('D9 the editor selector names unnamed and empty slots Saved Build N',function()
 Boot(1,World({[2]={name='',verified=true,echoes=E2}}))
 SlashCmdList.NEXUS('editor')
 local rows,menu=SelectorRows()
 C.setup(menu~=nil and menu:IsShown() and #rows==6,'D9: fixture: the selector lists the six declared Saved Builds',#rows)
 local text={}
 for i,r in ipairs(rows) do text[i]=V.Plain(r._label and r._label:GetText() or '') end
 local joined=table.concat(text,' | ')
 print('OBSERVED','D9 rows='..joined)
 C.expect((text[2] or ''):find('Saved Build 2',1,true)~=nil and (text[4] or ''):find('Saved Build 4',1,true)~=nil
  and (text[4] or ''):find('Empty',1,true)~=nil and (text[5] or ''):find('Saved Build 5',1,true)~=nil,
  'D9: an unnamed Saved Build and the declared slots with no data are named Saved Build N',joined)
 C.expect(not joined:find('Loadout',1,true),'D9: no selector row says Loadout',joined)
 C.guard(rows[2]~=nil and rows[2].enabled and rows[4]~=nil and not rows[4].enabled
  and rows[4].scripts.OnMouseDown==nil and rows[4].scripts.OnClick==nil and menu:GetHeight()==18+6*24,
  'D9: the unnamed row stays selectable, an Empty row stays disabled with no handler, the menu height is unchanged')
 Zero()
 local before=Effects()
 if rows[2] and rows[2].scripts.OnMouseDown then rows[2].scripts.OnMouseDown(rows[2],'LeftButton') end
 local ctx,target=Ctrl().EditingContext() or {},Ctrl().CreateTargetContext() or {}
 local after=Effects()
 C.guard((ctx.loadoutSlot or target.loadoutSlot)==2 and after.writes==before.writes and after.uploads==before.uploads
  and after.others==before.others and after.auto==before.auto,
  'D9: choosing the unnamed row selects Saved Build 2 by slot and writes, uploads or activates nothing',Describe(after))
end)

-- D10-D12 (M4 final review B1, NB2, NB13): states in which the HUD model has
-- no verified native active row. A missing verified row is not first-run:
-- the panel must not call a Saved Build's plan the first-run target, name a
-- native Wishlist slot as a Saved Build, claim an active Saved Build it has
-- not verified, or say "none captured" for an assignment being restored.
-- Real adapter, runtime, view model and the button's own tooltip. Each SETUP
-- shows the production state through the adapter's and the model's own
-- facts; each EXPECT is a positive destination line (the accepted M3 cut has
-- no destination lines, the 916d cut says first-run or none captured), with
-- the exclusions inside the same EXPECT; GUARDs are effects and assignments.
local function ModelFacts(model)
 local pr=type(model)=='table' and type(model.progress)=='table' and model.progress or {}
 local asg=type(model)=='table' and type(model.assignment)=='table' and model.assignment or {}
 return pr,asg,tostring(pr.activeSlot)..'/'..tostring(pr.wishlistName)..'/'..tostring(asg.state)
end
local function Link(slot)
 local links=Nexus.Store.State().loadoutWishlists or {}
 return type(links[slot])=='table' and links[slot].name or nil
end

C.scenario('D10 a kept Saved Build while a native Wishlist slot is active is not the first-run target',function()
 Boot(6)
 C.setup(A.SetLoadoutWishlist(6,106)==true,'D10: fixture: Saved Build 6 (Six) is assigned W-Six')
 Refresh()
 -- The server's native active slot becomes the Wishlist slot 106, above the
 -- declared Saved Builds: Nexus keeps Saved Build 6 (GameAdapter keptSavedBuild).
 H.perks.serverActiveSlot=106
 local model=Refresh()
 local slots=A.Slots() or {}
 local selected,kept=A.SelectedSavedBuild(slots)
 C.setup(slots.activeSlot==106 and selected==6 and kept==true,
  'D10: fixture: the native active slot is Wishlist slot 106 and Nexus keeps Saved Build 6',
  tostring(slots.activeSlot)..'/'..tostring(selected)..'/'..tostring(kept))
 local pr,asg,facts=ModelFacts(model)
 C.setup(tonumber(pr.activeSlot)==0 and pr.wishlistName=='W-Six' and asg.state=='ready',
  'D10: fixture: the HUD model has no verified active row and holds the kept Saved Build\'s ready plan W-Six',facts)
 Zero()
 local before=Effects()
 local tip=HeaderTip()
 print('OBSERVED','D10 tip='..tip)
 C.expect(Has(tip,'Destination: the selected Saved Build - not confirmed as the active Saved Build')
  and Has(tip,'Wishlist: W-Six (assigned)') and not Has(tip,'first-run') and not Has(tip,'106')
  and not Has(tip,'active in the game'),
  'D10: the destination is the selected Saved Build, not the first-run target, slot 106 or a verified active one',tip)
 C.guard(Same(Effects(),before),'D10: hovering writes, uploads, sends, requests and activates nothing',Describe(Effects()))
 C.guard(Link(6)=='W-Six','D10: Saved Build 6 keeps its assignment',Link(6))
end)

C.scenario('D11 a slot payload without the verified field is not read as the first-run target',function()
 Boot(2)
 C.setup(A.SetLoadoutWishlist(2,107)==true,'D11: fixture: Saved Build 2 (Fire PvE) is assigned W-Free')
 Refresh()
 -- No row now reads verified=false while the designed slots above the
 -- declared range read verified: the adapter's field-presence rule marks
 -- every row as lacking the verified field (GameAdapter ReadSlots).
 local rows=H.Clone(H.perks.serverBuildSlots)
 for _,row in pairs(rows) do row.verified=true end
 H.perks.serverBuildSlots=rows
 local model=Refresh()
 local slots=A.Slots() or {}
 local row=slots.bySlot and slots.bySlot[2] or {}
 C.setup(slots.activeSlot==2 and row.verifiedFieldPresent==false,
  'D11: fixture: native Saved Build 2 is active and the payload lacks the verified field',
  tostring(slots.activeSlot)..'/'..tostring(row.verifiedFieldPresent))
 local pr,asg,facts=ModelFacts(model)
 C.setup(tonumber(pr.activeSlot)==0 and pr.wishlistName=='W-Free' and asg.state=='ready',
  'D11: fixture: the HUD model has no verified active row and holds Saved Build 2\'s ready plan W-Free',facts)
 Zero()
 local before=Effects()
 local tip=HeaderTip()
 print('OBSERVED','D11 tip='..tip)
 C.expect(Has(tip,'Destination: the selected Saved Build - not confirmed as the active Saved Build')
  and Has(tip,'Wishlist: W-Free (assigned)') and not Has(tip,'first-run') and not Has(tip,"Saved Build 'Fire PvE'")
  and not Has(tip,'active in the game'),
  'D11: the destination is the selected Saved Build, not the first-run target, and no unverified row is named active',tip)
 C.guard(Same(Effects(),before),'D11: hovering writes, uploads, sends, requests and activates nothing',Describe(Effects()))
 C.guard(Link(2)=='W-Free','D11: Saved Build 2 keeps its assignment',Link(2))
end)

C.scenario('D12 a restoring assignment is not shown as nothing captured',function()
 Boot(1)
 C.setup(A.SetLoadoutWishlist(1,107)==true,'D12: fixture: Saved Build 1 (One) is assigned W-Free')
 Refresh()
 -- No Saved Build is natively active while a saved assignment exists: the
 -- adapter reports that it is restoring the assigned Wishlist.
 H.perks.serverActiveSlot=0
 local model=Refresh()
 local slots=A.Slots() or {}
 local pr,asg,facts=ModelFacts(model)
 C.setup(slots.activeKnown~=false and slots.activeSlot==0 and tonumber(pr.activeSlot)==0 and asg.state=='restoring',
  'D12: fixture: no Saved Build is active and the assignment is being restored',facts)
 Zero()
 local before=Effects()
 local tip=HeaderTip()
 print('OBSERVED','D12 tip='..tip)
 C.expect(Has(tip,'Destination: not known yet (the saved assignment is being restored)')
  and Has(tip,'Wishlist: restoring the saved assignment') and not Has(tip,'none captured') and not Has(tip,'first-run'),
  'D12: a restoring assignment is said as not known yet, not as nothing captured or first-run',tip)
 C.guard(Same(Effects(),before),'D12: hovering writes, uploads, sends, requests and activates nothing',Describe(Effects()))
 C.guard(Link(1)=='W-Free','D12: Saved Build 1 keeps its assignment',Link(1))
end)

-- D13 (I-01): a shortened name never splits an escaped pipe pair. Display text
-- doubles each literal pipe ("||", Identity.DisplaySafeText); a cut that keeps
-- only the first pipe of a pair leaves a lone pipe before the "...". Every cut
-- position of ASCII, 2-, 3- and 4-byte UTF-8, raw and already doubled pipes,
-- through SafeName, SavedBuildLabel and the Status lines that cut a recorded
-- Orb operation (60 characters) and an Auto note (200). Pipe-free names cut
-- exactly as before; whole names and the DestinationFields cells stay whole and
-- escaped once; the raw names a caller holds are unchanged. Pure projections
-- of the booted UserText (the last scenario's boot); a display-string check,
-- not a FontString or saved-data one.
local function Paired(text)
 if type(text)~='string' then return false end
 for run in text:gmatch('|+') do if #run%2~=0 then return false end end
 return true
end
local function Letters(text)
 local out={}
 for ch in text:gmatch('[\1-\127\194-\244][\128-\191]*') do out[#out+1]=ch end
 return out
end
-- Independent expectation for a pipe-free name: the first n letters and "...".
local function CutPlain(text,n)
 local letters=Letters(text)
 if #letters<=n then return text end
 return table.concat(letters,'',1,n)..'...'
end
C.scenario('D13 I-01: a cut name never splits an escaped pipe pair, at every cut position',function()
 local T,I=Nexus.UserText,Nexus.Identity
 C.setup(T and type(T.SafeName)=='function' and type(T.SavedBuildLabel)=='function' and type(T.StatusLines)=='function'
  and I and type(I.DisplaySafeText)=='function' and type(I.ValidUtf8)=='function','D13: fixture: the booted UserText and Identity')
 if not (T and I) then return end
 local plainBad,plainCases={},0
 for _,plain in ipairs({'Alice','\195\137clair','\231\129\171\229\134\176',THREE..'x'..FOUR}) do
  if T.SafeName(plain)~=plain then plainBad[#plainBad+1]='whole '..plain end
  for n=1,#Letters(plain)+1 do
   plainCases=plainCases+1
   local got=T.SafeName(plain,n)
   if got~=CutPlain(plain,n) or not I.ValidUtf8(got) then plainBad[#plainBad+1]=plain..' at '..n..': '..tostring(got) end
  end
 end
 C.guard(plainCases==20 and #plainBad==0,'D13: a pipe-free name is cut at the same letter as before and is whole without a limit',table.concat(plainBad,'; '))
 local raws={'ab|cd','\195\169clair|x','\231\129\171|\229\134\176',FOUR..'|'..FOUR,'ab||cd','|Alice','Alice|','A|B|C','|'}
 local held={}
 for i,raw in ipairs(raws) do held[i]=raw end
 local split,shape,cases={},{},0
 for _,raw in ipairs(raws) do
  local full=I.DisplaySafeText(raw,1024,false)
  if T.SafeName(raw)~=full then shape[#shape+1]='whole '..raw..': '..tostring(T.SafeName(raw)) end
  local letters=Letters(full or '')
  for n=1,#letters+1 do
   cases=cases+1
   local shown=T.SafeName(raw,n)
   local label=T.SavedBuildLabel(2,raw,n)
   if not (Paired(shown) and Paired(label) and I.ValidUtf8(shown) and I.ValidUtf8(label)) then
    split[#split+1]=raw..' at '..n..': '..tostring(shown)
   end
   -- The kept text is the start of the whole display text: n letters, or n-1
   -- when the n-th letter would be the first pipe of a pair; never more.
   local kept=n>=#letters and shown or (type(shown)=='string' and shown:match('^(.*)%.%.%.$'))
   local count=kept and #Letters(kept) or -1
   local prefix=kept~=nil and full:sub(1,#kept)==kept
   local fits=n>=#letters and kept==full
    or count==n or (count==n-1 and letters[n]=='|' and letters[n+1]=='|')
   if not (prefix and fits and label=="Saved Build '"..tostring(shown).."' (slot 2)") then
    shape[#shape+1]=raw..' at '..n..': '..tostring(shown)
   end
  end
 end
 print('OBSERVED','D13 pipe cut cases='..cases..' split='..#split..' shape='..#shape)
 C.expect(cases==63 and #split==0,'D13: no SafeName or SavedBuildLabel cut leaves a lone pipe or a broken letter',table.concat(split,'; '))
 C.guard(#shape==0,'D13: each cut keeps the start of the whole display text, at most maxChars letters, and the label wording',
  table.concat(shape,'; '))
 -- The Status lines' own cuts: a recorded Orb operation and an Auto note
 -- whose escaped pair straddles the 60- and 200-letter limits.
 local operation=string.rep('a',59)..'|x'
 local note=string.rep('b',199)..'|y'
 local lines=T.StatusLines({auto=true,autoNote=note,syncMode='off',orb={pending=true,operation=operation}})
 local status=table.concat(lines or {},'\n')
 print('OBSERVED','D13 status lines='..status)
 C.expect(Paired(status) and Has(status,"'"..string.rep('a',59).."...'") and Has(status,'not acting now: '..string.rep('b',199)..'...'),
  'D13: the Status lines cut the Orb operation and the Auto note before the escaped pair, not inside it',status)
 -- Whole names stay whole and escaped once; the caller's raw names are unchanged.
 local descriptor={kind='savedBuild',slot=2,name='ab|cd',character='\195\137clair|x',
  wishlist='Player|List',wishlistState='assigned',active=true}
 local fields=T.DestinationFields(descriptor)
 C.guard(fields[1].value=='\195\137clair||x' and fields[2].value=='ab||cd (slot 2)' and fields[3].value=='Player||List (assigned)',
  'D13: the DestinationFields cells keep each whole name escaped once and its assignment meaning',
  tostring(fields[1].value)..' / '..tostring(fields[2].value)..' / '..tostring(fields[3].value))
 local same=descriptor.name=='ab|cd' and descriptor.character=='\195\137clair|x' and descriptor.wishlist=='Player|List'
  and descriptor.wishlistState=='assigned' and operation==string.rep('a',59)..'|x' and note==string.rep('b',199)..'|y'
 for i,raw in ipairs(raws) do if held[i]~=raw then same=false end end
 C.guard(same,'D13: the raw Saved Build, player, Wishlist and recorded names a caller passed are unchanged')
end)

C.finish('(the panel names its destination and tells first-run, empty, unassigned and unavailable apart; captured editors are not redirected)')
