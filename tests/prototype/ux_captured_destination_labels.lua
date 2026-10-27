-- M1 (UX-04 confirmation naming and first-run label): Create and Save
-- confirmations name the destination the editor captured -- a Saved Build by
-- its name with the slot as second identity, the first-run target of the
-- character, or no destination -- never a Saved Build that became active
-- later, never slot 1 or a first-run target guessed for an empty or unknown
-- destination. With Auto ON the consequence line is conditional and names no
-- latency. The opened first-run plan is labelled as the first-run target.
-- Acceptance rows (inputs/FIRST_STAGE.md): M1-A02 first-run Create; A03 bound
-- Save naming an inactive Saved Build; A09 the active Saved Build switches
-- while editing; A10 a recycled server slot and a replaced editor context;
-- A11 long and unnamed Saved Builds; A13 Auto ON wording, nothing changed by
-- open/cancel; A14 empty Saved Build, unknown slot data and a reused server
-- slot keep their refusals with no slot/name/default fallback.
-- Since M2 the categories are relative to the accepted M1 cut: EXPECT is
-- behaviour added in M2 (F2/C5 captured-draft wording, F3 scoped unbound
-- Save line, F5 game-change wording, the chooser opened by Assign now);
-- GUARD is accepted M1 behaviour that must keep holding (absence checks are
-- paired with the presence they qualify). SETUP: fixture state.
-- Real TOC boot, adapter, controller, editor and Journal controls; synthetic
-- host services only. Nothing is set on the editor's state directly.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_captured_destination_labels')
local H,A,writes,spends
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local E3={{spellId=201176,quality=0,stacks=1}}
local E4={{spellId=201177,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local LONG='Fire PvE '..string.rep('Longname ',7)..'end'
local CHARACTER='PrototypeTester' -- the harness UnitName('player')
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}

local function Boot(o)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;EchoJournalMicroButton=nil
 NexusEditorFrame=nil;NexusWishlistNameInput=nil;NexusWishlistEditorSwitchButton=nil
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusWishlistAssignNowButton=nil
 NexusWishlistEditorLoadoutMenu=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201173,'Echo Six',0,5);H.AddEcho(201174,'Echo Free',0,5)
 H.AddEcho(201175,'Echo Fire',0,5);H.AddEcho(201176,'Echo Arena',0,5);H.AddEcho(201177,'Echo Four',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots=o.slots
 H.perks.serverActiveSlot=o.active
 spends=0
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function() spends=spends+1;return false end}
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
end
local function World(extra)
 local slots={[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [3]={name='Arena',verified=true,echoes=E3},[6]={name='Six',verified=true,echoes=E6},
  [106]={name='W-Six',verified=false,echoes=E6},[107]={name='W-Free',verified=false,echoes=EF}}
 for k,v in pairs(extra or {}) do slots[k]=v end
 return slots
end
local function Assign(slot,name,echoes)
 local ok,why=A.SetLoadoutWishlistIdentity(slot,name,H.Clone(echoes));assert(ok,why)
 writes.SetLoadoutWishlistIdentity=0
end
local function Ctrl()
 local show=Nexus.WishlistEditor.Show
 for i=1,255 do local n,v=debug.getupvalue(show,i);if not n then break end
  if n=='wishlistController' then return v end end
 error('editor controller not found')
end
local function Ctx() return Ctrl().EditingContext() or {} end
local function VisibleButton(text)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f:GetText()==text then return f end end
 return nil
end
-- M3: the editor's actions are named by their effect; a legacy label also
-- finds the action with that default intent (new label first, then legacy).
local LABELS={['Create Wishlist']={'Create & assign','Create unassigned','Create Wishlist'},
 ['Save Wishlist']={'Save & assign','Save changes','Save Wishlist'}}
local function button(text)
 for _,label in ipairs(LABELS[text] or {text})do
  local found=VisibleButton(label)
  if found then return found end
 end
 error('visible button absent: '..text)
end
-- The editor's own control with this label. The HUD's no-build setup row has
-- a "Create Wishlist" button too (it only opens the editor); it stays shown
-- beside an editor opened through OpenForCandidate while no Wishlist is
-- assigned, so a lookup by label alone can press that one instead.
local function EditorButton(text)
 for _,label in ipairs(LABELS[text] or {text})do
  for _,f in ipairs(H.frames)do
   if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame and f:GetText()==label then return f end
  end
 end
 return nil
end
local function selected(id)
 for _,f in ipairs(H.frames)do if f:IsVisible() and f.plus and f.data and f.data.spellId==id then return f end end
 error('visible selected row absent: '..id)
end
local function ClickCatalog(id)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==id then f:Click();return true end end
 error('visible catalog row absent: '..id)
end
local function menuRow(label)
 for _,f in ipairs(H.frames)do
  if f.kind=='Button' and f:IsVisible() and f._label and tostring(f._label:GetText() or ''):find(label,1,true) then return f end
 end
 error('visible switch-menu row absent: '..label)
end
local function Uploads() local n,last=0,nil;for _,a in ipairs(H.actions)do if a[1]=='upload' then n=n+1;last=a end end;return n,last end
local function Others() local n=0;for _,a in ipairs(H.actions)do if a[1]~='upload' then n=n+1 end end;return n end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Stored(where)
 local s=Nexus.Store.State()
 if where=='first' then return s.firstRunWishlist end
 return s.loadoutWishlists and s.loadoutWishlists[where]
end
local function Facts()
 local s=Nexus.Store.State() or {};local links=type(s.loadoutWishlists)=='table' and s.loadoutWishlists or {}
 local out={}
 for slot=1,6 do local r=links[slot]
  out[#out+1]=slot..'='..(type(r)=='table' and (tostring(r.name)..'/'..tostring(r.assignmentId)) or tostring(r)) end
 local f=s.firstRunWishlist
 out[#out+1]='first='..(type(f)=='table' and (tostring(f.name)..'/'..tostring(f.assignmentId)) or tostring(f))
 return table.concat(out,' ')
end
local function MirrorAt(slot,last)
 local rows=H.Clone(H.perks.serverBuildSlots or {});rows[slot]={name=last[3],verified=false,echoes=H.Clone(last[4])}
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll();H.Advance(4)
end
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return table.concat(heard,' / ')
end
-- The open confirmation as the client shows it (its text with the show
-- arguments substituted), or nil.
local function Asked()
 local p=H.popup;if not p then return nil end
 local d=StaticPopupDialogs[p.which] or {}
 local ok,s=pcall(string.format,tostring(d.text or ''),p.arg1,p.arg2)
 return V.Plain(ok and s or tostring(d.text or ''))
end
local function Cancel()
 local p=H.popup
 if p then StaticPopupDialogs[p.which].OnCancel(p.frame,p.data) end
 H.popup=nil
end
local function ResultRow()
 if not NexusEditorFrame then return nil end
 for _,r in ipairs(NexusEditorFrame.regions) do
  if r.kind=='FontString' and r:IsVisible() then
   local t=V.Plain(r:GetText() or '')
   if t:find('^Saved') or t:find('^Uploaded') or t:find('^Not saved') then return t,r end
  end
 end
 return nil
end
-- Every hover line of the result line, joined.
local function ResultHover()
 local _,r=ResultRow()
 if not r then return nil end
 for _,f in ipairs(NexusEditorFrame.children) do
  local p=f.points and f.points[1]
  if f.kind=='Frame' and p and p[2]==r and f:GetScript('OnEnter') then
   local lines=V.TooltipLines(function() f:GetScript('OnEnter')(f) end)
   return V.Plain(table.concat(lines,'\n'))
  end
 end
 return nil
end
local function ResultHoverFirstLine()
 local _,r=ResultRow()
 if not r then return nil end
 for _,f in ipairs(NexusEditorFrame.children) do
  local p=f.points and f.points[1]
  if f.kind=='Frame' and p and p[2]==r and f:GetScript('OnEnter') then
   local lines=V.TooltipLines(function() f:GetScript('OnEnter')(f) end)
   return lines[1] and V.Plain(lines[1]) or nil
  end
 end
 return nil
end
-- The editor's context line: the shown cells of its destination row, joined
-- in order; without that row (an older editor), the text anchored directly
-- under its title.
local function ContextLine()
 local row=NexusEditorFrame and NexusEditorFrame._destinationRow
 if type(row)=='table' and type(row.cells)=='table' then
  local shown={}
  for _,c in ipairs(row.cells) do
   if c:IsVisible() then shown[#shown+1]=V.Plain(c:GetText() or '') end
  end
  return table.concat(shown,' / ')
 end
 for _,r in ipairs(NexusEditorFrame and NexusEditorFrame.regions or {}) do
  local at=r.points and r.points[1]
  if r.kind=='FontString' and at and at[1]=='TOP' and type(at[2])=='table'
   and at[2].kind=='FontString' and at[3]=='BOTTOM' then
   return V.Plain(r:GetText() or '')
  end
 end
 return ''
end
local function AssignNowButton()
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame
   and V.Plain(f:GetText() or ''):find('^Assign now') then return f end
 end
 return nil
end
local function JournalHost()
 local journal=_G.ProjectEbonholdEchoJournal or CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
 journal:Hide()
 local micro=_G.EchoJournalMicroButton or CreateFrame('Button','EchoJournalMicroButton',UIParent)
 micro:SetScript('OnClick',function() journal:Show() end)
 return journal
end
local function Close() if NexusEditorFrame and NexusEditorFrame:IsShown() then Nexus.WishlistEditor.Toggle() end end
local function Quiet(tag,others,auto)
 C.guard(Others()==others and spends==0 and Auto()==auto,
  tag..': no Saved Build activation or save, roll, lock, tome or Orb call; Auto unchanged',
  'others='..Others()..' spends='..spends..' auto='..tostring(Auto()))
end
local function NewPlan(name,id)
 NexusWishlistNameInput:SetText(name);ClickCatalog(id)
 H.popup=nil
 button('Create Wishlist'):Click()
end
local function SaveClick(id)
 selected(id).plus:Click()
 H.popup=nil
 button('Save Wishlist'):Click()
end
local function BoundWorld(active,extra)
 Boot({active=active,slots=World(extra)})
 Assign(6,'W-Six',E6);H.Notify();A.Poll();H.Advance(1)
 local candidate
 for _,c in ipairs(A.GetWishlistCandidates())do if c.slot==106 then candidate=c end end
 Nexus.WishlistEditor.OpenForWishlist(candidate,6)
 C.setup(Ctx().loadoutSlot==6 and Ctx().name=='W-Six','fixture: W-Six is open for Saved Build 6',Ctx().name)
end
local BANNED={'within seconds','right away','immediately','will replace','at once'}
local function Conditional(text)
 local l=tostring(text or ''):lower()
 for _,w in ipairs(BANNED) do if l:find(w,1,true) then return false,w end end
 return true
end

C.scenario('A09 the active Saved Build switches while a new plan is edited',function()
 Boot({active=2,slots=World()})
 SlashCmdList.NEXUS('editor')
 local target=Ctrl().CreateTargetContext()
 C.setup(target and target.loadoutSlot==2,'A09: fixture: the draft captured Saved Build 2 (Fire PvE)')
 H.perks.serverActiveSlot=3;H.Notify();A.Poll();H.Advance(1)
 C.setup(A.Slots().activeSlot==3,'A09: fixture: Arena is the active Saved Build now')
 local others,auto=Others(),Auto()
 NewPlan('Captured',201175)
 local asked=Asked()
 print('OBSERVED','A09 confirmation='..tostring(asked))
 C.setup(asked~=nil,'A09: fixture: Create asks for confirmation')
 C.guard(asked and V.Names(asked,'Fire PvE') and asked:find('slot 2',1,true) and asked:find('captured',1,true),
  'A09: the confirmation names the captured Saved Build Fire PvE (slot 2)',asked)
 C.guard(asked and V.Names(asked,'Fire PvE') and not V.Names(asked,'Arena'),
  'A09: it names the captured Saved Build and never the one that became active',asked)
 H.AcceptPopup()
 C.guard(Stored(2) and Stored(2).name=='Captured' and Stored(3)==nil,'A09: the existing guards assign the captured Saved Build only',Facts())
 local row=ResultRow()
 C.guard(row and V.Names(row,'Fire PvE') and not V.Names(row,'Arena'),'A09: the result names Fire PvE, not Arena',row)
 Quiet('A09',others,auto)
 Close()
end)

C.scenario('A09 a draft begun with no Saved Build stays unassigned when one becomes active',function()
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 SlashCmdList.NEXUS('editor')
 C.setup(Ctrl().CreateTargetContext()==nil and not Ctrl().IsEditing(),'A09b: fixture: a new draft with no captured Saved Build')
 local rows=H.Clone(H.perks.serverBuildSlots);rows[1]={name='One',verified=true,echoes=E1}
 H.perks.serverBuildSlots=rows;H.perks.serverActiveSlot=1;H.Notify();A.Poll();H.Advance(1)
 local facts=Facts()
 NewPlan('Late',201174)
 local asked=Asked()
 print('OBSERVED','A09b confirmation='..tostring(asked))
 -- M2 F2: what the editor captured, not a claim about what was open.
 C.expect(asked and asked:find('The editor did not capture a Saved Build for this draft',1,true)
  and not asked:find('No Saved Build was open',1,true)
  and not asked:lower():find('first-run',1,true) and not V.Names(asked,'One'),
  'A09b: the confirmation says the editor captured no destination; no first-run, no newly active Saved Build',asked)
 if not asked then return end
 H.AcceptPopup()
 C.guard(Writes()==0 and Facts()==facts,'A09b: the save assigns nothing (unchanged)',Facts())
 local row=ResultRow()
 C.guard(row and row:find('Not assigned',1,true),'A09b: the result says it was saved without an assignment',row)
 C.expect(row and row:find('captured no Saved Build for this draft',1,true) and not row:find('no Saved Build was open',1,true),
  'A09b: the result names what the editor captured',row)
 Close()
end)

C.scenario('C5 a copied draft while a populated Saved Build is selected',function()
 Boot({active=1,slots=World()})
 local opened=Nexus.WishlistEditor.OpenForCandidate({title='Copied plan',echoes={{spellId=201174,quality=0,stacks=1}}})
 C.setup(opened and Ctrl().CreateTargetContext()==nil and not Ctrl().IsEditing() and A.Slots().activeSlot==1,
  'C5: fixture: a copied draft with no captured Saved Build while Saved Build One is selected')
 local facts,others,auto=Facts(),Others(),Auto()
 local create=EditorButton('Create Wishlist')
 C.setup(create~=nil,'C5: fixture: the editor\'s own Create Wishlist button is shown')
 if not create then return end
 H.popup=nil
 create:Click()
 local asked=Asked()
 print('OBSERVED','C5 confirmation='..tostring(asked))
 C.setup(asked~=nil,'C5: fixture: Create asks for confirmation')
 if not asked then return end
 C.expect(asked:find('did not capture a Saved Build',1,true)~=nil and not asked:find('No Saved Build was open',1,true),
  'C5: the confirmation does not claim no Saved Build was open',asked)
 H.AcceptPopup()
 C.guard(Uploads()==1 and Writes()==0 and Facts()==facts,'C5: saved once, assigned nowhere (unchanged)',Facts())
 local row=ResultRow()
 C.expect(row and row:find('captured no Saved Build',1,true)~=nil and not row:find('no Saved Build was open',1,true),
  'C5: the result does not claim no Saved Build was open',row)
 C.guard(Others()==others and Auto()==auto and spends==0,'C5: no other game action, Auto unchanged')
 Close()
end)

C.scenario('A02 first-run Create, label and Save',function()
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 SlashCmdList.NEXUS('editor')
 C.setup(Ctrl().CreateTargetContext()==nil,'A02: fixture: a new draft on a character with no Saved Build')
 local others,auto=Others(),Auto()
 NewPlan('Starter',201174)
 local asked=Asked()
 print('OBSERVED','A02 confirmation='..tostring(asked))
 C.setup(asked~=nil,'A02: fixture: Create asks for confirmation')
 C.guard(asked and asked:find('first-run target for '..CHARACTER,1,true),
  'A02: the confirmation names the first-run target of the character',asked)
 C.guard(asked and asked:find('first-run target for '..CHARACTER,1,true)
  and not asked:find('slot',1,true) and not asked:find('Saved Build 1',1,true),
  'A02: it names the first-run target and invents no Saved Build slot',asked)
 local said=Heard(function() H.AcceptPopup() end)
 local n,last=Uploads()
 C.guard(n==1 and Stored('first') and Stored('first').name=='Starter' and writes.SetFirstLoadoutWishlistIdentity==1,
  'A02: the same first-run assignment as before',Facts())
 C.guard(said:find('first-run Wishlist target',1,true)~=nil,'A02: the existing chat line is kept',said)
 local row=ResultRow()
 print('OBSERVED','A02 row='..tostring(row))
 C.guard(row and row:find('^Saved') and row:find('First-run target for '..CHARACTER,1,true) and not row:find('slot',1,true),
  'A02: the result names the first-run target of the character',row)
 -- M2 F5: the slot-1 hand-off is a Nexus record, not a game change.
 local hover=ResultHover() or ''
 C.expect(hover:find('No Saved Build was activated or changed in the game',1,true)~=nil
  and not hover:find('No Saved Build was changed.',1,true),
  'F5: the first-run result says no Saved Build was activated or changed in the game',hover)
 MirrorAt(108,last)
 Close()
 SlashCmdList.NEXUS('editor')
 C.setup(Ctx().name=='Starter' and Ctx().destination=='first','A02: fixture: the first-run plan is open again')
 local line=ContextLine()
 print('OBSERVED','A02 context='..line)
 C.guard(line:find('Saved Build: ',1,true)~=nil and not line:find('Assigned to:',1,true),
  'A02: the header keeps its Saved Build wording and claims no assignment',line)
 C.guard(line:find('first-run target',1,true)~=nil,'A02: the opened first-run plan is labelled as the first-run target',line)
 SaveClick(201174)
 asked=Asked()
 C.guard(asked and asked:find('first-run target for '..CHARACTER,1,true),'A02: the Save confirmation names the first-run target',asked)
 Cancel()
 C.guard(Uploads()==n,'A02: cancelling uploads nothing')
 Quiet('A02',others,auto)
 Close()
end)

C.scenario('A14 an empty captured Saved Build is refused, never first-run or slot 1',function()
 Boot({active=2,slots=World()})
 SlashCmdList.NEXUS('editor')
 C.setup(Ctrl().CreateTargetContext() and Ctrl().CreateTargetContext().loadoutSlot==2,'A14: fixture: draft captured Saved Build 2')
 local rows=H.Clone(H.perks.serverBuildSlots);rows[2]={name='Fire PvE',verified=true,echoes={}}
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll();H.Advance(1)
 local facts,others,auto=Facts(),Others(),Auto()
 NewPlan('Empty',201175)
 C.guard(H.popup==nil and Uploads()==0 and Writes()==0 and Facts()==facts,
  'A14: no confirmation, upload or assignment; no first-run or slot-1 fallback',Facts())
 local row=ResultRow()
 print('OBSERVED','A14 empty row='..tostring(row))
 C.guard(row and row:find('^Not saved') and V.Names(row,'Fire PvE') and row:find('empty or not loaded',1,true)
  and not row:lower():find('first-run',1,true),'A14: a not-saved result names the empty captured Saved Build',row)
 Quiet('A14',others,auto)
 Close()
end)

C.scenario('A14 unknown slot data: no guessed destination; Assign now waits for it',function()
 Boot({active=nil,slots=World()})
 C.setup(A.Slots() and A.Slots().activeKnown==false,'A14u: fixture: the active Saved Build is unknown')
 SlashCmdList.NEXUS('editor')
 C.setup(Ctrl().CreateTargetContext()==nil and not Ctrl().IsEditing(),'A14u: fixture: a new draft with no captured destination')
 local facts=Facts()
 NewPlan('Unknown',201175)
 local asked=Asked()
 print('OBSERVED','A14u confirmation='..tostring(asked))
 C.guard(asked and asked:find('not loaded yet',1,true) and not asked:lower():find('first-run',1,true)
  and not asked:find('slot',1,true),'A14u: the confirmation says the destination is unknown; nothing guessed',asked)
 if not asked then return end
 H.AcceptPopup()
 C.guard(Uploads()==1 and Writes()==0 and Facts()==facts,'A14u: saved once, assigned nowhere (unchanged)',Facts())
 local row=ResultRow()
 C.guard(row and row:find('Not assigned',1,true) and row:find('not loaded',1,true),'A14u: the result says why it is not assigned',row)
 local journal=JournalHost()
 local btn=AssignNowButton()
 C.guard(btn~=nil,'A14u: Assign now is offered for the saved, unassigned plan')
 if not btn then return end
 local sent=#H.sent
 local said=Heard(function() btn:Click() end)
 C.guard(said:find('not loaded yet',1,true)~=nil and NexusEditorFrame:IsShown() and not journal:IsShown(),
  'A14u: while slot data is unknown, Assign now opens nothing',said)
 C.guard(Uploads()==1 and Writes()==0 and #H.sent==sent,'A14u: and uploads, assigns or sends nothing')
 H.perks.serverActiveSlot=1;H.Notify();A.Poll();H.Advance(1)
 btn=AssignNowButton()
 C.setup(btn~=nil,'A14u: fixture: Assign now still offered')
 if not btn then return end
 sent=#H.sent
 btn:Click()
 C.guard(not NexusEditorFrame:IsShown() and journal:IsShown(),'A14u: once loaded, Assign now opens the Echo Journal')
 -- M2 UX-06: the Journal's chooser itself is open, titled with its target.
 local picker=_G.NexusWishlistOnlyPicker
 local title=picker and picker.title and V.Plain(picker.title:GetText() or '') or ''
 C.expect(picker~=nil and picker:IsShown() and title:find('Assign to',1,true)~=nil and V.Names(title,'One'),
  'A14u: the chooser opens titled with the Saved Build it assigns to',title)
 C.guard(Uploads()==1 and Writes()==0 and #H.sent==sent,'A14u: opening it uploads, assigns or sends nothing')
end)

C.scenario('A03 bound Save of an inactive Saved Build names it',function()
 BoundWorld(1)
 local others,auto=Others(),Auto()
 local sent=#H.sent
 SaveClick(201173)
 local asked=Asked()
 print('OBSERVED','A03 confirmation='..tostring(asked))
 C.guard(asked and V.Names(asked,'Six') and asked:find('slot 6',1,true) and asked:find('updates its assignment',1,true),
  'A03: the Save confirmation names Saved Build Six (slot 6) and that its assignment is updated',asked)
 C.guard(asked and V.Names(asked,'Six') and not V.Names(asked,'One'),
  'A03: it names Saved Build Six and never the active Saved Build One',asked)
 Cancel()
 C.guard(Uploads()==0 and Writes()==0 and #H.sent==sent,'A03: opening and cancelling upload, assign and send nothing')
 Quiet('A03',others,auto)
 Close()
end)

C.scenario('unbound Save names no Saved Build and promises no assignment',function()
 BoundWorld(6)
 NexusWishlistEditorSwitchButton:Click();menuRow('W-Free'):Click()
 C.setup(Ctx().name=='W-Free' and Ctx().loadoutSlot==nil,'U: fixture: W-Free (no Saved Build) is open')
 SaveClick(201174)
 local asked=Asked() or ''
 print('OBSERVED','U confirmation='..asked)
 C.guard(V.Names(asked,'W-Free') and not asked:lower():find('assign',1,true) and not V.Names(asked,'Six'),
  'U: the confirmation updates W-Free and promises no assignment',asked)
 C.guard(asked:find('no Saved Build',1,true)~=nil,'U: it says there is no Saved Build here',asked)
 -- M2 F3: scoped to this editor and this save, not a global claim.
 C.expect(asked:find('This editor has no Saved Build destination',1,true)~=nil
  and not asked:find("saving changes no Saved Build's Wishlist",1,true),
  'F3: the unbound Save line is scoped to this editor and this save',asked)
 Cancel()
 C.guard(Uploads()==0,'U: cancelling uploads nothing')
 Close()
end)

C.scenario('A13 Auto ON consequence wording; open and cancel change nothing',function()
 Boot({active=1,slots=World({[101]={name='W-One',verified=false,echoes=E1}})})
 Assign(1,'W-One',E1);H.Notify();A.Poll();H.Advance(1)
 SlashCmdList.NEXUS('auto');H.Advance(.2,.1)
 C.setup(Auto(),'A13: fixture: Auto is ON')
 SlashCmdList.NEXUS('editor')
 C.setup(Ctx().name=='W-One' and Ctx().loadoutSlot==1,'A13: fixture: W-One is open for Saved Build One')
 local others,uploads=Others(),Uploads()
 local sent=#H.sent
 SaveClick(201172)
 local asked=Asked() or ''
 print('OBSERVED','A13 bound confirmation='..asked)
 C.guard(asked:find('Auto is ON',1,true)~=nil and asked:find('may replace',1,true)~=nil and asked:find('level 80',1,true)~=nil
  and V.Names(asked,'One'),'A13: the bound Save names the conditional Auto consequence for Saved Build One',asked)
 local ok,word=Conditional(asked)
 C.guard(asked:find('Auto is ON',1,true)~=nil and ok,'A13: the Auto line is present and promises no unconditional replacement or latency',word)
 Cancel()
 C.guard(Auto() and Others()==others and Uploads()==uploads and #H.sent==sent,
  'A13: opening and cancelling keep Auto ON and change or send nothing')
 button('+ New Wishlist'):Click()
 C.setup(Ctrl().CreateTargetContext() and Ctrl().CreateTargetContext().loadoutSlot==1,'A13: fixture: a new draft for Saved Build One')
 NewPlan('Planned',201176)
 asked=Asked() or ''
 print('OBSERVED','A13 create confirmation='..asked)
 C.guard(asked:find('Auto is ON',1,true)~=nil and V.Names(asked,'One'),'A13: Create names the conditional Auto consequence',asked)
 ok,word=Conditional(asked)
 C.guard(asked:find('Auto is ON',1,true)~=nil and ok,'A13: Create\'s Auto line promises no immediate replacement',word)
 Cancel()
 C.guard(Auto() and Others()==others and Uploads()==uploads and spends==0,'A13: the Create confirmation and its cancel change nothing')
 Close()
 SlashCmdList.NEXUS('editor')
 NexusWishlistEditorSwitchButton:Click();menuRow('W-Free'):Click()
 C.setup(Ctx().name=='W-Free','A13: fixture: W-Free is open')
 SaveClick(201174)
 asked=Asked() or ''
 C.guard(not asked:find('Auto',1,true) and not asked:lower():find('assign',1,true),
  'A13: an unbound Save names no Auto consequence and no assignment',asked)
 Cancel()
 SlashCmdList.NEXUS('auto');H.Advance(.2,.1)
 C.setup(not Auto(),'A13: fixture: Auto is OFF again')
 Close();SlashCmdList.NEXUS('editor')
 button('+ New Wishlist'):Click()
 NewPlan('Quiet',201176)
 asked=Asked() or ''
 C.guard(V.Names(asked,'One') and not asked:find('Auto is ON',1,true),'A13: with Auto OFF the destination is named and no Auto line is added',asked)
 Cancel()
 C.guard(Uploads()==uploads and spends==0,'A13: nothing was uploaded or spent')
 Close()
end)

C.scenario('A11 long and unnamed Saved Build names',function()
 Boot({active=2,slots=World({[2]={name=LONG,verified=true,echoes=E2},[4]={name='',verified=true,echoes=E4}})})
 SlashCmdList.NEXUS('editor')
 C.setup(Ctrl().CreateTargetContext() and Ctrl().CreateTargetContext().loadoutSlot==2,'A11: fixture: draft captured the long-named Saved Build 2')
 NewPlan('Long',201175)
 local asked=Asked() or ''
 C.guard(asked:find(LONG,1,true)~=nil and asked:find('slot 2',1,true)~=nil,'A11: the confirmation carries the complete captured name',asked)
 H.AcceptPopup()
 local row=ResultRow()
 C.guard(row and row:find(LONG,1,true),'A11: the result carries the complete name (the client shortens the line)',row)
 C.guard(row and ResultHoverFirstLine()==row,'A11: hovering the result shows its complete text',ResultHoverFirstLine())
 H.Advance(4)
 H.perks.serverActiveSlot=4;H.Notify();A.Poll();H.Advance(1)
 button('+ New Wishlist'):Click()
 C.setup(Ctrl().CreateTargetContext() and Ctrl().CreateTargetContext().loadoutSlot==4,'A11: fixture: draft captured unnamed Saved Build 4')
 NewPlan('Unnamed',201177)
 asked=Asked() or ''
 print('OBSERVED','A11 unnamed confirmation='..asked)
 C.guard(asked:find('Saved Build 4',1,true)~=nil and not asked:find("'Saved Build 4'",1,true) and not V.Names(asked,'Fire'),
  'A11: an unnamed Saved Build is named by its slot only, never by another name',asked)
 Cancel()
 Close()
end)

C.scenario('A10/A14 a recycled server slot keeps its refusal and shows it',function()
 BoundWorld(6)
 local rows=H.Clone(H.perks.serverBuildSlots);rows[106]={name='Other',verified=false,echoes=EF}
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll();H.Advance(1)
 local facts=Facts()
 SaveClick(201173)
 C.guard(H.popup==nil and Uploads()==0 and Facts()==facts,'A10: the reused slot is not overwritten; nothing is assigned',Facts())
 local row=ResultRow()
 print('OBSERVED','A10 reused row='..tostring(row))
 C.guard(row and row:find('^Not saved') and row:find('no longer holds the Wishlist this editor opened',1,true)
  and not row:find('Assigned',1,true),'A10: a not-saved result explains the reused server slot',row)
 Close()
end)

C.scenario('A10 a replaced editor context retires the result',function()
 BoundWorld(6)
 selected(201173).plus:Click();button('Save Wishlist'):Click();H.AcceptPopup()
 local row=ResultRow()
 C.guard(row and row:find('Assigned to',1,true),'A10: the bound save is assigned',row)
 local others=Others()
 -- Choose Saved Build 1 with the editor's real Saved Build selector.
 local selector
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:GetParent()==NexusEditorFrame and f._arrow~=nil and f~=NexusWishlistEditorSwitchButton then selector=f end
 end
 C.setup(selector~=nil,'A10: fixture: the Saved Build selector exists')
 if not selector then return end
 selector:Click()
 local menu=_G.NexusWishlistEditorLoadoutMenu
 local entry=menu and menu.rows and menu.rows[1]
 C.setup(entry~=nil and entry:GetScript('OnMouseDown')~=nil,'A10: fixture: the selector offers Saved Build 1')
 if not entry then return end
 entry:GetScript('OnMouseDown')(entry,'LeftButton')
 H.Advance(2)
 C.setup(Ctx().loadoutSlot==nil and Ctrl().CreateTargetContext() and Ctrl().CreateTargetContext().loadoutSlot==1,
  'A10: fixture: the editor now edits Saved Build 1')
 C.guard(row~=nil and ResultRow()==nil,'A10: the earlier result is gone in the new context',ResultRow())
 C.guard(Others()==others and H.perks.serverActiveSlot==6,'A10: choosing a Saved Build activates nothing')
 Close()
end)

-- Destination row (helper successor): the real four-cell rows of the editor
-- and the HUD, read as shown. EXPECT: behaviour of that row (a source
-- without it fails one expectation and returns, never a setup); GUARD: the
-- editor's existing quiet refresh. Geometry is the offline font model of
-- layout_geometry_support, not native measurement.
local G=dofile('tests/prototype/layout_geometry_support.lua')
-- The four cells of a real destination row as shown (plain text), and each
-- way one is not: not visible, wider than its own width, outside the row or
-- overlapping another cell (one line: horizontal extents).
local function RowCells(row)
 local texts,bad,rects={},{},{}
 local width=row:GetWidth()
 if #row.cells~=4 then bad[#bad+1]=#row.cells..' cells' end
 for i=1,4 do
  local c=row.cells[i]
  texts[i]=''
  if type(c)~='table' or c.kind~='FontString' or not c:IsVisible() or (c:GetText() or '')=='' then
   bad[#bad+1]='cell'..i..' not shown'
  else
   texts[i]=V.Plain(c:GetText())
   if c:GetStringWidth()>c:GetWidth() then
    bad[#bad+1]='cell'..i..' '..texts[i]..' measures '..c:GetStringWidth()..' in '..c:GetWidth()
   end
   local placed,r=pcall(G.Rect,c,row)
   if not placed then
    bad[#bad+1]='cell'..i..' not placed'
   else
    if r[1]<0 or r[3]>width then bad[#bad+1]='cell'..i..' outside the row '..G.Text(r) end
    for j,o in pairs(rects) do
     if r[1]<o[3] and o[1]<r[3] then bad[#bad+1]='cells '..j..' and '..i..' overlap' end
    end
    rects[i]=r
   end
  end
 end
 return texts,bad
end

C.scenario('the editor destination row keeps naming the captured Saved Build Six',function()
 BoundWorld(6)
 C.setup(NexusEditorFrame and NexusEditorFrame:IsVisible(),'R-ED: fixture: the real editor is shown')
 local row=NexusEditorFrame and NexusEditorFrame._destinationRow
 local has=type(row)=='table' and type(row.cells)=='table'
 C.expect(has,'R-ED: the editor shows its destination row of cells')
 if not has then return end
 local function Shown(tag)
  local t,bad=RowCells(row)
  local all=table.concat(t,' / ')
  print('OBSERVED','R-ED '..tag..' row='..all)
  C.expect(#bad==0,'R-ED '..tag..': four visible cells, each within its own width, disjoint inside the row',table.concat(bad,'; '))
  C.expect(t[1]:find(CHARACTER,1,true) and V.Names(t[2],'Six')
   and (t[2]:find('slot 6)',1,true) or (t[2]:find('#6',1,true) and not t[2]:find('#6%d')))
   and t[3]:find('W-Six',1,true) and t[4]:find('Captured',1,true)
   and not V.Names(all,'One') and not t[2]:find('slot 1)',1,true) and not t[2]:find('#1',1,true),
   'R-ED '..tag..': it shows '..CHARACTER..', the captured Six (slot 6), W-Six and Captured, never One',all)
 end
 Shown('opened')
 H.perks.serverActiveSlot=1;H.Notify();A.Poll();H.Advance(1)
 C.setup(A.Slots().activeSlot==1,'R-ED: fixture: Saved Build One is active now')
 Nexus.WishlistEditor.Refresh()
 Shown('after One became active')
 C.guard(Ctx().loadoutSlot==6 and Ctx().name=='W-Six','R-ED: the editor still edits W-Six for Saved Build 6',Ctx().loadoutSlot)
 -- Settled: five more real refreshes read only Level and act on nothing.
 -- Public methods are wrapped and counted, then restored before leaving.
 local reads={'Slots','Wishlist','GetLoadoutWishlist','AssignedWishlist','GetFirstRunWishlist','SelectedSavedBuild'}
 local counts,restore={},{}
 local function Count(t,k,label)
  local real=t[k]
  if type(real)~='function' then return end
  counts[label]=0;restore[#restore+1]=function() t[k]=real end
  t[k]=function(...) counts[label]=counts[label]+1;return real(...) end
 end
 local actions,sent,w,sp,auto=#H.actions,#H.sent,Writes(),spends,Auto()
 for _,k in ipairs(reads) do Count(A,k,k) end
 Count(A,'Level','Level');Count(Nexus.Store,'State','Store.State');Count(_G,'UnitName','UnitName')
 local ok,err=pcall(function() for _=1,5 do Nexus.WishlistEditor.Refresh() end end)
 for i=#restore,1,-1 do restore[i]() end
 reads[#reads+1]='Store.State';reads[#reads+1]='UnitName'
 local zero,profile=true,{'Level='..tostring(counts.Level)}
 for _,k in ipairs(reads) do
  profile[#profile+1]=k..'='..tostring(counts[k])
  if (counts[k] or 0)~=0 then zero=false end
 end
 print('OBSERVED','R-ED warm '..table.concat(profile,','))
 C.expect(ok and counts.Level==5 and zero,
  'R-ED: five warm refreshes read Level 5 times and no slot, Wishlist, assignment, first-run, selected Saved Build, Store or UnitName',
  ok and table.concat(profile,',') or err)
 C.guard(#H.actions==actions and #H.sent==sent and Writes()==w and spends==sp and Auto()==auto,
  'R-ED: they activate, save, send, assign, spend and change Auto nothing')
 Close()
end)

C.scenario('the Play header keeps an empty long-named Saved Build 123 readable at the 2.0 font scale',function()
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 -- The double font model is set for this case only. The four region font
 -- methods, the model and the font object as they were before it are
 -- restored on every exit (a return, a failed check or a raised error,
 -- which is raised again after the restore), and a following boot is
 -- checked against the font object, size and model found before it.
 local KEYS={'GetStringHeight','GetStringWidth','GetTextWidth','GetFont'}
 local methods,saved=G.RegionMethods(),{}
 for _,k in ipairs(KEYS) do saved[k]=rawget(methods,k) end
 local savedModel,savedObject=G.model,rawget(_G,'NexusFontNormal')
 -- The font object the runtime font scale reads, and the size it reports.
 local function Font()
  local object=rawget(_G,'NexusFontNormal')
  if type(object)~='table' or type(object.GetFont)~='function' then return object,nil end
  local got,_,size=pcall(object.GetFont,object)
  return object,got and size or nil
 end
 local beforeObject,beforeSize=Font()
 local fitted,err=pcall(function()
  G.UseFont(G.MODELS.double)
  local ok,res=pcall(Nexus.Panel.Render,{character=CHARACTER,
   progress={activeSlot=123,activeSlotName='Long \195\169cho | field '..string.rep('wide ',12),wishlistName='W-Free',
    owned=0,total=2,missing={},shed={},unknownTomes={},toLock={},isCommunityPreview=false},
   assignment={state='ready',name='W-Free',emptySlot=true},cards={},auto=false,level=40})
  C.setup(ok and res~=false,'R-HUD: fixture: the real HUD renders the synthetic model',res)
  local panel=_G.NexusPanel
  local labels=panel and {panel._contextTitle,panel._contextBuild,panel._contextWishlist} or {}
  local hits=panel and {panel._contextTitleHit,panel._contextBuildHit,panel._contextWishlistHit} or {}
  local has=#labels==3 and #hits==3
  C.expect(has and panel._destinationRow and not panel._destinationRow:IsShown(),
   'R-HUD: the three-line Play header replaces the cramped four-cell row')
  if not (ok and has) then return end
  local shown,tip,bad={},{},{}
  for i=1,3 do
   local label,hit=labels[i],hits[i]
   shown[i]=V.Plain(label:GetText())
   if not label:IsVisible() or not hit:IsVisible() or shown[i]=='' then
    bad[#bad+1]='line '..i..' is not visible'
   end
   local placed,r=pcall(G.Rect,label,panel)
   if not placed then bad[#bad+1]='line '..i..' is not placed'
   elseif r[1]<0 or r[3]>panel:GetWidth() or r[2]<0 or r[4]>panel:GetHeight() then
    bad[#bad+1]='line '..i..' outside panel '..G.Text(r)
   end
   local enter=hit:GetScript('OnEnter')
   local lines,healthy={},false
   if enter then lines,healthy=V.TooltipLines(enter,hit) end
   if not healthy then bad[#bad+1]='line '..i..' hover is unavailable' end
   tip[i]=V.Plain(table.concat(lines,'\n'))
   local leave=hit:GetScript('OnLeave');if leave then leave(hit) end
  end
  local all=table.concat(shown,' / ')
  print('OBSERVED','R-HUD header='..all)
  C.expect(#bad==0,'R-HUD: three visible, placed lines with working full-text hover',table.concat(bad,'; '))
  C.expect(shown[1]:find('Nexus',1,true) and shown[2]:find('Build:',1,true)
   and shown[3]:find('Wishlist:',1,true),
   'R-HUD: the header visibly identifies the destination categories',all)
  local disclosure=table.concat(tip,'\n')
  C.expect(disclosure:find('Character: '..CHARACTER,1,true)
   and disclosure:find('slot 123)',1,true)
   and disclosure:find(string.rep('wide ',11)..'wide',1,true)
   and disclosure:find('holds no Echoes',1,true),
   'R-HUD: hovering the header discloses the full empty Saved Build destination',disclosure)
 end)
 for _,k in ipairs(KEYS) do methods[k]=saved[k] end
 G.model,_G.NexusFontNormal=savedModel,savedObject
 local changed={}
 for _,k in ipairs(KEYS) do if not rawequal(rawget(methods,k),saved[k]) then changed[#changed+1]=k end end
 if not rawequal(G.model,savedModel) then changed[#changed+1]='model' end
 if not rawequal(rawget(_G,'NexusFontNormal'),savedObject) then changed[#changed+1]='NexusFontNormal' end
 C.setup(#changed==0,'R-HUD: fixture: the four region font methods, the font model and the font object are restored',
  table.concat(changed,', '))
 if not fitted then error(err,0) end
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 local object,size=Font()
 C.setup(rawequal(object,beforeObject) and size==beforeSize and rawequal(G.model,savedModel),
  'R-HUD: fixture: after the next boot the font object, its size and the font model are those found before the double model',
  tostring(object)..'/'..tostring(size)..' before '..tostring(beforeObject)..'/'..tostring(beforeSize)..' model='..tostring(G.model and G.model.name))
end)

-- C (Preview classification): a Community Build preview's title
-- (progress.wishlistName while progress.isCommunityPreview) names the
-- previewed build, never destination or assignment authority. With no
-- active slot and the assignment unassigned or missing, the actual shown HUD
-- row and its hover disclosure read the same with and without that title:
-- Preview over the underlying "none captured", never unconfirmed. An
-- unavailable Preview and an ordinary (non-Preview) title keep their
-- classification. Show runs before the injected Renders and nothing
-- advances before a row is read, so no refresh replaces the injected model.
-- Nothing is written to the panel; each hover is left again.
C.scenario('C: a Preview title alone is not destination authority',function()
 Boot({slots={},active=0})
 local P=Nexus.Panel
 if not C.setup(type(P)=='table' and type(P.Show)=='function' and type(P.Render)=='function'
  and type(P.DestinationFacts)=='function','C: Panel has Show, Render and DestinationFacts') then return end
 local TITLE,STATE_LINE='CommunityOnlyTitle','State: Preview; None captured'
 local function Model(state,title,preview)
  local m={character=CHARACTER,progress={owned=0,total=0,missing={},shed={},unknownTomes={},toLock={},
   isCommunityPreview=preview},assignment={},cards={},auto=false,level=40}
  if state then m.assignment.state=state end
  if title then m.progress.wishlistName=title end
  return m
 end
 -- The full state line is disclosed by the first header line's hover.
 local function NonePreview(text)
  return text=='State: Preview; None captured'
 end
 -- The Wishlist disclosure segments, and whether one names the title.
 local function Wishlists(tip)
  local n,titled=0,false
  for seg in tip:gmatch('Wishlist:[^\n]*') do n=n+1;titled=titled or seg:find(TITLE,1,true)~=nil end
  return n,titled
 end
 -- The shown header for model m: its facts, three labels, state disclosure,
 -- and every full-text hover (OnEnter, then OnLeave).
 local function Shown(m,label)
  local facts=P.DestinationFacts(m) or {}
  P.Render(m)
  local row=NexusPanel and NexusPanel._destinationRow
  local labels={NexusPanel._contextTitle,NexusPanel._contextBuild,NexusPanel._contextWishlist}
  local hits={NexusPanel._contextTitleHit,NexusPanel._contextBuildHit,NexusPanel._contextWishlistHit}
  if not C.setup(#labels==3 and #hits==3 and row and not row:IsShown(),
   'C: three-line Play header replaces hidden destination row ('..label..')') then return nil end
  local texts,visible={},true
  for i=1,3 do visible=visible and labels[i]:IsVisible();texts[i]=V.Plain(labels[i]:GetText()) end
  C.setup(visible,'C: Play header labels are shown ('..label..')')
  local lines,ran,healthy={},0,true
  for _,hit in ipairs(hits) do
   local enter=type(hit)=='table' and type(hit.GetScript)=='function' and hit:GetScript('OnEnter')
   if type(enter)=='function' then
    local got,ok=V.TooltipLines(enter,hit)
    ran,healthy=ran+1,healthy and ok
    for _,line in ipairs(got) do lines[#lines+1]=V.Plain(line) end
    local leave=hit:GetScript('OnLeave')
    if type(leave)=='function' then pcall(leave,hit) end
   end
  end
  C.setup(ran==3 and healthy,'C: all Play header lines disclose on hover ('..label..')',ran)
  texts[4]=hits[1]._nexusFull and hits[1]._nexusFull:match('State:[^\n]*') or ''
  return {facts=facts,cells=texts,tip=table.concat(lines,'\n')}
 end
 P.Show()
 for _,state in ipairs({'unassigned',false}) do
  local label=state and ('assignment '..state) or 'assignment state missing'
  -- The titled model renders first, after a different model, so its row is
  -- laid out afresh rather than kept from the untitled one.
  local titled=Shown(Model(state or nil,TITLE,true),label..', titled')
  local plain=Shown(Model(state or nil,nil,true),label..', untitled')
  if not (titled and plain) then return end
  C.guard(plain.facts.kind=='none','C: untitled Preview is kind none ('..label..')',plain.facts.kind)
  C.expect(titled.facts.kind=='none','C: a Preview title alone keeps kind none ('..label..')',titled.facts.kind)
  C.guard(plain.facts.wishlist==nil and titled.facts.wishlist==nil,
   'C: a Preview title is no Wishlist fact ('..label..')',titled.facts.wishlist)
  C.guard(NonePreview(plain.cells[4]),'C: untitled Preview shows none under Preview ('..label..')',plain.cells[4])
  C.expect(NonePreview(titled.cells[4]),
   'C: titled Preview shows none under Preview, not unconfirmed ('..label..')',titled.cells[4])
  local same,named=true,false
  for i=1,4 do
   same=same and titled.cells[i]==plain.cells[i]
   named=named or titled.cells[i]:find(TITLE,1,true)~=nil
  end
  C.expect(same,'C: shown header is the same with and without the Preview title ('..label..')',
   table.concat(titled.cells,' / ')..' vs '..table.concat(plain.cells,' / '))
  C.guard(not named,'C: no shown header line names the Preview title ('..label..')',table.concat(titled.cells,' / '))
  -- The disclosure, checked apart from the shown text.
  C.guard(plain.tip:find(STATE_LINE,1,true)~=nil,'C: untitled Preview discloses '..STATE_LINE..' ('..label..')',plain.tip)
  C.expect(titled.tip:find(STATE_LINE,1,true)~=nil,'C: titled Preview discloses '..STATE_LINE..' ('..label..')',titled.tip)
  local n,bad=Wishlists(titled.tip)
  C.guard(n>0 and not bad,'C: titled Preview discloses a Wishlist that is not the Preview title ('..label..')',titled.tip)
  C.expect(titled.tip==plain.tip,'C: disclosure is the same with and without the Preview title ('..label..')',titled.tip)
 end
 -- Unchanged branches (facts only): an unavailable Preview stays
 -- unconfirmed; an ordinary (non-Preview) title stays unconfirmed and is
 -- that plan's Wishlist; an ordinary untitled plan stays none.
 for _,case in ipairs({
  {state='unavailable',title=TITLE,preview=true,kind='unconfirmed',label='unavailable titled Preview'},
  {state='unavailable',preview=true,kind='unconfirmed',label='unavailable untitled Preview'},
  {state='unassigned',title='OrdinaryTitle',kind='unconfirmed',wishlist='OrdinaryTitle',label='ordinary title, unassigned'},
  {title='OrdinaryTitle',kind='unconfirmed',wishlist='OrdinaryTitle',label='ordinary title, state missing'},
  {state='unassigned',kind='none',label='ordinary untitled plan, unassigned'},
 }) do
  local facts=P.DestinationFacts(Model(case.state,case.title,case.preview)) or {}
  C.guard(facts.kind==case.kind and facts.wishlist==case.wishlist,'C: '..case.label..' keeps kind '..case.kind,
   tostring(facts.kind)..' / '..tostring(facts.wishlist))
 end
end)
-- B2 (destination fit priority; fixture only): the reopened first-run plan
-- keeps its captured first-run target in the real 900 px destination row at
-- the largest supported font scale. The real A02 lifecycle runs for a short
-- and a long plan name. In the double model the compact whole state fits
-- (188+67+133+287, plus 12 for 3 gaps, = 687 <= 900). A long name needs only
-- the plan name shortened, never the early minimum (C:1). EXPECT: row
-- behaviour (a missing row fails one expectation and returns). GUARD: the
-- row keeps its 900 px width. SETUP: fixture state. Font methods, model and
-- font object are restored before returning. Offline font model; native
-- NOT_RUN.
C.scenario('B2 first-run row keeps its captured first-run target at font scale 2',function()
 local KEYS={'GetStringHeight','GetStringWidth','GetTextWidth','GetFont'}
 local savedObject,savedModel=rawget(_G,'NexusFontNormal'),G.model
 -- The plan name as shown: whole, or its start cut with an ellipsis.
 local function NameShown(text,name)
  if text:find(name,1,true) then return true end
  local head=name:match('^%S+') or name
  local at=text:find(head,1,true)
  if not at then return false end
  local shown=text:sub(at):gsub('%.%.%.$',''):gsub('\226\128\166$',''):gsub('%s+$','')
  return #shown>=#head and name:sub(1,#shown)==shown
 end
 -- Every line the row's own visible hover areas write (OnEnter, then OnLeave).
 local function Hover(row)
  local hits,lines,errs=row.hits,{},{}
  local list=type(hits)=='table' and (hits.kind and {hits} or hits) or {}
  for _,hit in pairs(list) do
   local enter=type(hit)=='table' and hit.kind and hit:IsVisible() and hit:GetScript('OnEnter')
   if enter then
    local got,ok,err=V.TooltipLines(function()
     enter(hit)
     local leave=hit:GetScript('OnLeave')
     if leave then leave(hit) end
    end)
    if not ok then errs[#errs+1]=V.printable(err) end
    for _,line in ipairs(got) do lines[#lines+1]=line end
   end
  end
  return V.Plain(table.concat(lines,'\n')),table.concat(errs,'; ')
 end
 local function Case(name,font)
  local tag='B2 '..name
  Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
  SlashCmdList.NEXUS('editor')
  NewPlan(name,201174)
  local asked=Asked()
  C.setup(asked~=nil,tag..': fixture: Create asks for confirmation')
  if not asked then return end
  H.AcceptPopup()
  local n,last=Uploads()
  local first=Stored('first')
  local saved=n==1 and last~=nil and type(first)=='table' and first.name==name
  C.setup(saved,tag..': fixture: the first-run plan is saved under its exact name',Facts())
  if not saved then return end
  MirrorAt(108,last)
  Close()
  SlashCmdList.NEXUS('editor')
  local ctx=Ctx()
  local opened=ctx.name==name and ctx.destination=='first' and NexusEditorFrame~=nil and NexusEditorFrame:IsVisible()
  C.setup(opened,tag..': fixture: the first-run plan is open again under its exact name',tostring(ctx.name)..'/'..tostring(ctx.destination))
  if not opened then return end
  local refresh=Nexus.WishlistEditor and Nexus.WishlistEditor.Refresh
  C.setup(type(refresh)=='function',tag..': fixture: the editor refreshes through its public Refresh')
  if type(refresh)~='function' then return end
  font.methods=G.RegionMethods()
  for _,k in ipairs(KEYS) do font.saved[k]=rawget(font.methods,k) end
  G.UseFont(G.MODELS.double)
  refresh()
  local row=NexusEditorFrame._destinationRow
  local present=type(row)=='table' and type(row.cells)=='table' and type(row.GetWidth)=='function'
   and type(row.IsVisible)=='function' and row:IsVisible()
  C.expect(present,tag..': the editor shows its destination row')
  if not present then return end
  C.guard(row:GetWidth()==900,tag..': the destination row keeps its 900 px width',row:GetWidth())
  local texts,bad=RowCells(row)
  local shown=table.concat(texts,' / ')
  local detail=shown..' | '..table.concat(bad,'; ')
  print('OBSERVED',tag..' double row='..detail)
  C.expect(#bad==0,tag..': the four cells are shown, fit and stay apart at font scale 2',detail)
  local cue=texts[4]
  C.expect(shown:find('first-run target',1,true) and cue:find('first-run target',1,true)
   and (cue:find('^Captured') or cue:find('^C:')),
   tag..': the row keeps the captured first-run target (Captured or C: cue), not C:1',detail)
  C.expect((texts[1]:find('^Character:') or texts[1]:find('^C:')) and texts[1]:find(CHARACTER,1,true)
   and (texts[2]:find('^Saved Build') or texts[2]:find('^B:')) and texts[2]:find('None',1,true)
   and (texts[3]:find('^Wishlist') or texts[3]:find('^W:')) and NameShown(texts[3],name),
   tag..': the cells keep their categories, the character, no Saved Build and the plan name',detail)
  local hover,errs=Hover(row)
  print('OBSERVED',tag..' hover='..hover)
  C.expect(hover:find(name,1,true)~=nil and V.Names(hover,name),
   tag..': the hover names the full plan exactly',hover..' '..errs)
  C.expect(hover:find('first-run target',1,true)~=nil,
   tag..': the hover names the captured first-run target',hover..' '..errs)
 end
 for _,name in ipairs({'Starter','Starter With A Longer Plan Name'}) do
  local font={saved={}}
  _G.NexusFontNormal=nil
  local ok,err=pcall(Case,name,font)
  local closed,closeErr=pcall(Close)
  if font.methods then for _,k in ipairs(KEYS) do font.methods[k]=font.saved[k] end end
  G.model,_G.NexusFontNormal=savedModel,savedObject
  if not ok then error(err,0) end
  if not closed then error(closeErr,0) end
 end
end)

-- Origins: a new draft that captured no destination shows the current facts
-- in its destination row by the Journal's rule, never a capture. No Saved
-- Build in use is the first-run target. A populated Saved Build selected now
-- (also the one kept while a Wishlist above maxSlots is natively active) is
-- none captured, never that Saved Build. An unreadable active slot or a
-- missing row is not loaded yet. The row never shows a captured first-run
-- target, a stale begin origin or a retarget. EXPECT: the shown Saved Build
-- and State cells, then the row's own hover once they are shown (the opened
-- and copy cases above keep the capture policy). GUARD: no capture,
-- assignment, game effect or Auto change. Fixture state is read through
-- the public Slots and SelectedSavedBuild ports only; no role is set.
do
 local ALPHA={name='Alpha',verified=true,echoes=E1}
 -- The full, compact and minimum values of the Saved Build and State cells.
 local WORDS={
  firstRun={build={'none in use','none'},state={'first-run target (no saved build in use)','first run','1st'}},
  none={build={'none captured','?'},state={'none captured','none'}},
  unknown={build={'not loaded yet','?'},state={'saved build data is not loaded yet','not loaded','?'}},
 }
 local function Esc(s) return (s:gsub('(%p)','%%%1')) end
 -- A positive capture cue; the negative None captured is not one.
 local function Captures(text)
  local t=V.Plain(text):lower():gsub('none captured','')
  return t:find('captured',1,true)~=nil or t:find('%f[%w]c:')~=nil
 end
 -- A name or a slot that this draft never captured.
 local function Mentions(text,bad)
  local t=V.Plain(text):lower()
  for _,b in ipairs(bad) do
   if type(b)=='number' then
    for _,p in ipairs({'slot%s*','#','build%s+'}) do
     if t:find(p..b..'%f[%D]') then return b end
    end
   elseif V.Names(t,b) then return b end
  end
  return nil
 end
 -- One shown cell value: whole, case-insensitive, with an optional label.
 local function In(s,list,label)
  s=s:lower():gsub('^%s+',''):gsub('%s+$',''):gsub('^'..label..':%s*','')
  for _,v in ipairs(list) do if s==v then return true end end
  return false
 end
 local function Set(active,alpha)
  local rows=H.Clone(H.perks.serverBuildSlots or {})
  if alpha then rows[1]=H.Clone(ALPHA) end
  H.perks.serverBuildSlots=rows;H.perks.serverActiveSlot=active
  H.Notify();A.Poll();H.Advance(2)
 end
 -- Fixture state through the public ports only (a read observes and sets nothing).
 local function Port(tag,active,sel,kept,alpha)
  local s=A.Slots()
  if not C.expect(type(A.SelectedSavedBuild)=='function','Origins '..tag..': the public SelectedSavedBuild port exists') then return nil end
  local got,isKept=A.SelectedSavedBuild(s)
  local rows=type(s)=='table' and type(s.bySlot)=='table' and s.bySlot or {}
  local one=type(rows[1])=='table' and #(rows[1].echoes or {}) or 0
  local known=type(s)=='table' and ((active==nil and s.activeKnown==false)
   or (active~=nil and s.activeKnown~=false and s.activeSlot==active))
  local ok=known and got==sel and (isKept==true)==kept and (one>0)==alpha and rows[2]==nil
  local seen=type(s)=='table' and (tostring(s.activeKnown)..'/'..tostring(s.activeSlot)..' row1='..one
   ..' selected='..tostring(got)..'/'..tostring(isKept)) or 'no slots'
  return C.setup(ok,'Origins '..tag..': fixture: native active '..tostring(active or 'unreadable')
   ..', selected Saved Build '..tostring(sel)..(kept and ' (kept)' or ''),seen) and s or nil
 end
 local function Begun(tag)
  return C.setup(NexusEditorFrame and NexusEditorFrame:IsShown() and Ctrl().CreateTargetContext()==nil
   and not Ctrl().IsEditing(),'Origins '..tag..': fixture: a new draft that captured no Saved Build')
 end
 local function NoTarget(tag)
  C.guard(Ctrl().CreateTargetContext()==nil and not Ctrl().IsEditing(),
   'Origins '..tag..': the draft still captured no Saved Build and edits none')
 end
 -- Every line that the row's own public hover writes.
 local function Hover(row)
  local hits=type(row.hits)=='table' and (rawget(row.hits,'kind') and {row.hits} or row.hits) or {}
  local lines,n,raised={},0,nil
  for _,f in pairs(hits) do
   local enter=type(f)=='table' and rawget(f,'kind') and f:IsVisible() and f:GetScript('OnEnter')
   if enter then
    n=n+1
    local got,ok,err=V.TooltipLines(enter,f)
    if not ok then raised=V.printable(err) end
    for _,l in ipairs(got) do lines[#lines+1]=V.Plain(l) end
    local leave=f:GetScript('OnLeave')
    if leave then pcall(leave,f) end
   end
  end
  return table.concat(lines,' / '),n,raised
 end
 local function Row(tag,kinds,bad)
  local row=NexusEditorFrame and NexusEditorFrame:IsVisible() and NexusEditorFrame._destinationRow
  if not C.expect(type(row)=='table' and type(row.cells)=='table','Origins '..tag..': the editor shows its destination row') then return end
  local t,why=RowCells(row)
  local line=table.concat(t,' / ')
  C.expect(#why==0,'Origins '..tag..': the four cells are shown whole inside the row',line..' ('..table.concat(why,'; ')..')')
  if #row.cells~=4 or t[1]=='' or t[2]=='' or t[3]=='' or t[4]=='' then return end
  local kind
  for _,k in ipairs(kinds) do
   if In(t[2],WORDS[k].build,'saved build') and In(t[4],WORDS[k].state,'state') then kind=k end
  end
  C.expect(kind~=nil and not Captures(line) and not Mentions(line,bad),
   'Origins '..tag..': the shown Saved Build and State cells read '..table.concat(kinds,' or ')
   ..' with no capture cue and no Saved Build it did not capture',line)
  local tip,n,raised=Hover(row)
  local w,low=WORDS[kind or kinds[1]],tip:lower()
  C.expect(n>0 and raised==nil and low:find('saved build:?%s*'..Esc(w.build[1]))~=nil
   and low:find('state:?%s*'..Esc(w.state[1]))~=nil and not Captures(tip) and not Mentions(tip,bad),
   'Origins '..tag..': the row hover then states that whole meaning with nothing captured',raised or tip)
 end
 local function Run(label,fn)
  C.scenario('Origins '..label,function()
   local ok,err=pcall(fn)
   pcall(Close)
   if not ok then error(err,0) end
  end)
 end
 Run('A: a new draft at native 0 follows the populated, kept and missing current facts',function()
  Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
  local others,auto,facts=Others(),Auto(),Facts()
  local bad={'Alpha','W-Free',1}
  if not Port('A0',0,nil,false,false) then return end
  SlashCmdList.NEXUS('editor');H.Advance(1)
  if not Begun('A0') then return end
  -- No Saved Build in use: the current first-run target or none, never captured.
  Row('A0 native 0',{'firstRun','none'},bad)
  Set(1,true)
  if Port('A1',1,1,false,true) then Row('A1 Saved Build 1 populated and active',{'none'},bad) end
  NoTarget('A1')
  -- Wishlist 107 is above maxSlots, so the kept Saved Build 1 stays selected.
  Set(107)
  if Port('A2',107,1,true,true) then Row('A2 Wishlist 107 active, Saved Build 1 kept',{'none'},bad) end
  NoTarget('A2')
  Set(2)
  local s=Port('A3',2,2,false,true)
  if s then
   Row('A3 native 2 without its row',{'unknown'},{'Alpha','W-Free',1,2})
   local P=Ctrl().DestinationPresentation
   if C.expect(type(P)=='function','Origins A3: the controller has DestinationPresentation') then
    local d0,d1=P(s,CHARACTER,0),P(s,CHARACTER,1)
    local ok=type(d0)=='table' and type(d1)=='table'
    C.expect(ok and d0.kind=='unknown' and d1.kind=='unknown' and d0.captured~=true and d1.captured~=true
     and d0.slot==nil and d1.slot==nil,
     'Origins A3: a selected scalar that differs from native 2 (0 or 1) stays unknown, never first-run or Saved Build 1',
     ok and (tostring(d0.kind)..'/'..tostring(d1.kind)) or 'no descriptor')
   end
  end
  NoTarget('A3')
  Quiet('Origins A',others,auto)
  C.guard(Writes()==0 and Facts()==facts,'Origins A: no assignment written (unchanged)',Facts())
 end)
 Run('B: a draft begun while the active slot is unreadable follows the known facts',function()
  Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
  local others,auto,facts=Others(),Auto(),Facts()
  local bad={'Alpha','W-Free',1}
  Set(nil)
  if not Port('B0',nil,nil,false,false) then return end
  SlashCmdList.NEXUS('editor');H.Advance(1)
  if not Begun('B0') then return end
  Row('B0 active slot unreadable',{'unknown'},bad)
  Set(0)
  if Port('B1',0,nil,false,false) then Row('B1 native 0 now known',{'firstRun'},bad) end
  Set(1,true)
  if Port('B2',1,1,false,true) then Row('B2 Saved Build 1 populated and active',{'none'},bad) end
  NoTarget('B2')
  Quiet('Origins B',others,auto)
  C.guard(Writes()==0 and Facts()==facts,'Origins B: no assignment written (unchanged)',Facts())
 end)
end
-- Lifecycle and read profile of the destination row's held observation
-- (the view-only Panel.destinationSessionRevision). An uncaptured draft,
-- begun at active 0 and then naturally observing the populated Saved Build
-- 1, holds a current observation; the HUD is hidden (Panel.Hide) while the
-- editor stays shown. Only real world events (H.Fire), Main's existing HUD
-- capture (Nexus.RefreshHudView) and natural server revisions (H.perks,
-- H.Notify, A.Poll) drive it; that one public scalar is assigned only for
-- the corruption control and restored on every exit. EXPECT: a new,
-- missing, malformed or other revision drops the held facts, which do not
-- revive (not by a fresh capture of the same name, not by the restored
-- token) before the next natural cold observation. GUARD: accepted
-- behaviour (cached character, reacquisition, captured Saved Build, warm
-- read profile, no effect). SETUP: fixture state, including that each
-- measured refresh stayed warm, so only the revision can drop the facts.
-- Cells are read as shown (RowCells); the full identity from the row's own
-- hover areas only after that. Offline synthetic only; native NOT RUN.
do
 local NOT_LOADED={label='Saved Build data not loaded yet',build={'Not loaded yet','?'},
  state={'Saved Build data is not loaded yet','Not loaded','?'},
  tip={{'saved build','not loaded yet'},{'state','saved build data is not loaded yet'}}}
 local NONE={label='no destination captured',build={'None captured','?'},state={'None captured','None'},
  tip={{'saved build','none captured'},{'state','none captured'}}}
 local FIRST={label='the first-run target',build={'None in use','None'},
  state={'First-run target (no Saved Build in use)','First run','1st'},
  tip={{'saved build','none in use'},{'state','first-run target (no saved build in use)'}}}
 local function Esc(s) return (tostring(s):lower():gsub('(%p)','%%%1')) end
 -- Shown text (an optional Label: prefix aside) that is one of the literal
 -- alternatives, or one of them cut at its end.
 local function Is(text,alternatives,label)
  local shown=V.Plain(text):lower()
  for _,t in ipairs({shown,label and shown:match('^'..Esc(label)..':%s*(.-)$') or nil}) do
   local stem=t:match('^(.-)%.%.%.$') or t:match('^(.-)\226\128\166$')
   for _,a in ipairs(alternatives) do
    a=a:lower()
    if t==a or (stem and #stem>=3 and #stem<#a and a:sub(1,#stem)==stem) then return true end
   end
  end
  return false
 end
 local function Has(tip,pair) return tip:find(Esc(pair[1])..':?%s*'..Esc(pair[2]))~=nil end
 local function ValidRev(v) return type(v)=='number' and v>=0 and v<math.huge and v==math.floor(v) end
 -- The editor's destination row as shown, then, only while it is shown,
 -- every line its own hover areas disclose (plain, lower case).
 local function Read()
  local row=NexusEditorFrame and NexusEditorFrame._destinationRow
  local s={t={'','','',''},bad={'no destination row'},tip=''}
  if type(row)=='table' and type(row.cells)=='table' then
   s.t,s.bad=RowCells(row)
   local lines={}
   if row:IsVisible() and type(row.hits)=='table' then
    for _,h in ipairs(row.hits) do
     local enter=type(h)=='table' and h:IsVisible() and h:GetScript('OnEnter')
     if enter then
      for _,l in ipairs((V.TooltipLines(function() enter(h) end))) do lines[#lines+1]=V.Plain(l):lower() end
      local leave=h:GetScript('OnLeave');if leave then pcall(leave,h) end
     end
    end
   end
   s.tip=table.concat(lines,'\n')
  end
  s.detail=table.concat(s.t,' | ')..(#s.bad>0 and (' bad='..table.concat(s.bad,'; ')) or '')
  return s
 end
 local function Shows(kind,tag,s,want)
  C[kind](#s.bad==0 and Is(s.t[2],want.build,'saved build') and Is(s.t[4],want.state,'state'),
   tag..': the shown Saved Build and State cells read '..want.label,s.detail)
  C[kind](Has(s.tip,want.tip[1]) and Has(s.tip,want.tip[2]) and not s.tip:find('shown as captured earlier',1,true),
   tag..': the row hover, read once shown, discloses '..want.label..', not captured',(s.tip:gsub('\n',' / ')))
 end
 local function Person(tag,s,known)
  C.guard(#s.bad==0 and Is(s.t[1],known and {CHARACTER} or {'Not known','?'},'character')
   and Has(s.tip,{'character',known and CHARACTER or 'not known'}),
   tag..': the shown character cell and hover read '..(known and CHARACTER or 'not known'),s.detail)
 end
 -- The one public view scalar, assigned for fn only and restored on every exit.
 local function WithRev(value,fn)
  local panel=Nexus.Panel
  local prior=panel.destinationSessionRevision
  panel.destinationSessionRevision=value
  local ok,err=pcall(fn)
  panel.destinationSessionRevision=prior
  if not ok then error(err,0) end
 end

 C.scenario('lifecycle: world sessions, revision corruption and warm reads of the destination row',function()
  Boot({active=0,slots=World()})
  local P,Ed=Nexus.Panel,Nexus.WishlistEditor
  local slash=SlashCmdList and SlashCmdList.NEXUS
  if not (type(P)=='table' and type(P.Hide)=='function' and type(P.CachedDestinationCharacter)=='function'
   and type(Ed)=='table' and type(Ed.Refresh)=='function' and type(Nexus.RefreshHudView)=='function'
   and type(slash)=='function') then
   C.expect(false,'lifecycle: the public editor, HUD hide, cached character and HUD capture exist');return
  end
  slash('editor');Nexus.RefreshHudView();Ed.Refresh()
  local found,ctl=pcall(Ctrl)
  if not found then C.expect(false,'lifecycle: the editor controller is reachable',ctl);return end
  local function Uncaptured()
   local c,t=Ctx(),type(ctl.CreateTargetContext)=='function' and ctl.CreateTargetContext() or nil
   return c.loadoutSlot==nil and c.name==nil and not (type(t)=='table' and tonumber(t.loadoutSlot))
  end
  C.setup(NexusEditorFrame and NexusEditorFrame:IsVisible() and Uncaptured(),
   'lifecycle: a new draft is open at active 0 and captured no destination')
  local row=NexusEditorFrame and NexusEditorFrame._destinationRow
  if type(row)~='table' or type(row.cells)~='table' then
   C.expect(false,'lifecycle: the editor shows its destination row');return
  end
  local s=Read()
  Shows('guard','begun at active 0',s,FIRST);Person('begun at active 0',s,true)
  local n,restore,noName={},{},false
  -- Counting wrappers of existing public getters, server reads and UnitName.
  local function Wrap(t,k,key,via)
   local real=t[k]
   if type(real)~='function' then return end
   n[key]=0
   t[k]=function(...) n[key]=n[key]+1;if via then return via(real,...) end;return real(...) end
   restore[#restore+1]=function() t[k]=real end
  end
  local ok,err=pcall(function()
   for _,w in ipairs({{A,'Slots','slots'},{A,'SelectedSavedBuild','selected'},{A,'GetLoadoutWishlist','loadout'},
    {A,'Wishlist','wishlist'},{A,'Level','level'},{H.service,'GetServerBuildSlots','backend'},
    {H.service,'GetServerActiveSlot','active'}}) do Wrap(w[1],w[2],w[3]) end
   Wrap(_G,'UnitName','unit',function(real,unit,...) if noName and unit=='player' then return nil end;return real(unit,...) end)
   local function Reads() return (n.slots or 0)+(n.selected or 0)+(n.backend or 0)+(n.active or 0) end
   local function Profile(d)
    local out={}
    for _,k in ipairs({'slots','selected','loadout','wishlist','backend','active','unit','level'}) do
     out[#out+1]=k..'='..(d[k] or 0)
    end
    return table.concat(out,' ')
   end
   -- A natural server revision: its existing cold reads are expected and
   -- counted here, apart from the warm profile.
   local function Server(tag,active)
    local r0=Reads()
    H.perks.serverActiveSlot=active;H.Notify();A.Poll();H.Advance(1);Ed.Refresh()
    C.setup(Reads()>r0,tag..': the natural server revision to active '..active..' made its existing reads',Reads()-r0)
    return Read()
   end
   local function Refresh(tag)
    local r0=Reads()
    Ed.Refresh()
    C.setup(Reads()==r0 and NexusEditorFrame:IsVisible(),
     tag..': the editor stays shown and this refresh is warm (no Slots, selected or server slot read)',Reads()-r0)
    return Read()
   end
   local function Char(tag,want)
    local u=n.unit or 0
    local count,value=select('#',P.CachedDestinationCharacter()),P.CachedDestinationCharacter()
    C.guard(count==1 and value==want and (n.unit or 0)==u,
     tag..': the cached character is '..tostring(want)..' (one value, no UnitName read)',
     tostring(value)..' values='..count..' reads='..((n.unit or 0)-u))
   end
   -- Five quiet public refreshes: their reads and whether the row held still.
   local function Warm()
    local before=Read()
    local s0={}
    for k,v in pairs(n) do s0[k]=v end
    for _=1,5 do Ed.Refresh() end
    local d,idle={},0
    for k,v in pairs(n) do d[k]=v-(s0[k] or 0);if k~='level' then idle=idle+d[k] end end
    return d,idle==0 and table.concat(before.t,'|')==table.concat(Read().t,'|')
   end
   s=Server('natural active 1',1)
   Shows('guard','natural active 1',s,NONE);Person('natural active 1',s,true)
   C.guard(Uncaptured(),'natural active 1: the draft adopted no Saved Build',Ctx().loadoutSlot)
   local token=P.destinationSessionRevision
   C.expect(ValidRev(token),'lifecycle: the Panel publishes a valid world-session revision',token)
   local d0,idle0=Warm()
   C.guard(idle0 and (d0.level or 0)==5,
    'quiet before: five warm refreshes read Level 5 times and no Slots, selected, Wishlist, server slot or UnitName; the row holds still',Profile(d0))
   local others,w0,u0,auto,facts=Others(),Writes(),(Uploads()),Auto(),Facts()
   restore[#restore+1]=function() if type(P.Show)=='function' then P.Show() end end
   P.Hide()
   C.setup(NexusEditorFrame:IsVisible(),'lifecycle: the HUD is hidden and the editor stays shown')
   H.Fire('PLAYER_LEAVING_WORLD');Char('leave',nil)
   local left=P.destinationSessionRevision
   C.expect(ValidRev(left) and left~=token,'leave: a new valid world-session revision is published',tostring(token)..' -> '..tostring(left))
   s=Refresh('leave');Shows('expect','leave',s,NOT_LOADED);Person('leave',s,false)
   Nexus.RefreshHudView();Char('capture while leaving',nil)
   s=Refresh('capture while leaving');Shows('expect','capture while leaving',s,NOT_LOADED);Person('capture while leaving',s,false)
   H.Fire('PLAYER_ENTERING_WORLD');Char('entry alone',nil)
   local entered=P.destinationSessionRevision
   C.expect(ValidRev(entered) and ValidRev(left) and entered>left,'entry: a newer valid world-session revision is published',
    tostring(left)..' -> '..tostring(entered))
   s=Refresh('entry alone');Shows('expect','entry alone',s,NOT_LOADED);Person('entry alone',s,false)
   local u=n.unit or 0
   Nexus.RefreshHudView()
   C.guard((n.unit or 0)>u,'fresh capture: Main made its existing UnitName read',(n.unit or 0)-u)
   Char('fresh capture',CHARACTER)
   s=Refresh('fresh capture of the same name');Shows('expect','fresh capture of the same name',s,NOT_LOADED)
   Person('fresh capture of the same name',s,true)
   noName=true;Nexus.RefreshHudView();noName=false;Char('unknown capture',nil)
   s=Refresh('unknown capture');Shows('expect','unknown capture',s,NOT_LOADED);Person('unknown capture',s,false)
   Nexus.RefreshHudView();Char('known again',CHARACTER)
   s=Refresh('known again');Shows('expect','known again',s,NOT_LOADED);Person('known again',s,true)
   local d1,idle1=Warm()
   C.guard(idle1 and (d1.level or 0)==(d0.level or 0),
    'quiet after: the dropped facts force no cold refresh and add no read; the row holds still',Profile(d1)..'; before '..Profile(d0))
   -- Corruption control: each case first reacquires the current truth
   -- through the next natural cold observation.
   local seq={2,0,1,0,2,1,0}
   local cases={{'negative',-1},{'fractional',2.5},{'infinite',math.huge},{'not a number',0/0},
    {'a string','1'},{'another valid integer'},{'missing',nil,true}}
   for i,case in ipairs(cases) do
    local tag='revision '..case[1]
    s=Server(tag,seq[i])
    Shows('guard',tag..': the next natural cold observation reacquires',s,seq[i]==0 and FIRST or NONE)
    local prior=P.destinationSessionRevision
    if not ValidRev(prior) then C.expect(false,tag..': a prior valid revision exists to restore',prior);break end
    WithRev(case[1]=='another valid integer' and prior+3 or case[2],function()
     s=Refresh(tag);Shows('expect',tag,s,NOT_LOADED);Person(tag,s,true)
     if case[3] then
      s=Server(tag..', cold',1)
      Shows('expect',tag..': a cold observation without a valid revision is not held',s,NOT_LOADED)
     end
    end)
    C.setup(rawequal(P.destinationSessionRevision,prior),tag..': the prior valid revision is restored',P.destinationSessionRevision)
    s=Refresh(tag..' restored');Shows('expect',tag..' restored',s,NOT_LOADED);Person(tag..' restored',s,true)
   end
   s=Server('final',2)
   Shows('guard','final: the next natural cold observation reacquires',s,NONE)
   C.guard(Uncaptured(),'corruption: the draft adopted no Saved Build',Ctx().loadoutSlot)
   H.Fire('PLAYER_LOGOUT');Char('logout',nil)
   Nexus.RefreshHudView();Char('capture after logout',nil)
   Ed.Refresh();Person('logout',Read(),false)
   Quiet('lifecycle',others,auto)
   C.guard(Writes()==w0 and (Uploads())==u0 and Facts()==facts,'lifecycle: no assignment write, upload or stored assignment change',
    'writes='..Writes()..'/'..w0..' uploads='..(Uploads())..'/'..u0..' '..Facts())
  end)
  noName=false
  for i=#restore,1,-1 do pcall(restore[i]) end
  if not ok then error(err,0) end
 end)

 C.scenario('lifecycle: a captured Saved Build survives world and revision invalidations',function()
  BoundWorld(1)
  local P,Ed=Nexus.Panel,Nexus.WishlistEditor
  local row=NexusEditorFrame and NexusEditorFrame._destinationRow
  if not (type(P)=='table' and type(P.Hide)=='function' and type(Ed)=='table' and type(Ed.Refresh)=='function'
   and type(Nexus.RefreshHudView)=='function' and type(row)=='table' and type(row.cells)=='table') then
   C.expect(false,'captured: the public editor, HUD hide, HUD capture and destination row exist');return
  end
  -- Healthy capture (setup only). BoundWorld opens the W-Six candidate,
  -- which carries no Saved Build name, so its Six is only the current row
  -- shown, never a captured name. Saved Build 6 is selected through the
  -- controller's public SelectLoadout, which the editor's own Saved Build
  -- selector calls: it reads the row name Six and opens the linked W-Six
  -- with it. Nothing is activated, saved or assigned; the effects baseline
  -- below is still taken after this.
  local ctl,picked,mode=Ctrl(),false,nil
  if type(ctl.SelectLoadout)=='function' then picked,mode=ctl.SelectLoadout(6) end
  Ed.Refresh()
  local cap=Ctx()
  C.setup(picked==true and mode=='wishlist' and cap.loadoutSlot==6 and cap.name=='W-Six' and cap.loadoutName=='Six',
   'captured: fixture: selecting Saved Build 6 captured its name Six with W-Six before any invalidation',
   tostring(picked)..'/'..tostring(mode)..' '..tostring(cap.loadoutSlot)..'/'..tostring(cap.name)..'/'..tostring(cap.loadoutName))
  local restore={}
  local ok,err=pcall(function()
   Nexus.RefreshHudView()
   local others,w0,u0,auto,facts=Others(),Writes(),(Uploads()),Auto(),Facts()
   -- Current facts may be dropped (an unstated active state is allowed); the
   -- captured slot and name stay, never active and never retargeted.
   local function Held(tag,known)
    Ed.Refresh()
    local s=Read()
    local state=V.Plain(s.t[4]):lower()
    state=state:match('^state:%s*(.-)$') or state
    local claimsActive=state=='c:+' or state=='captured: active'
     or (state:find('^captured; active')~=nil and state:find('^captured; active state')==nil)
    C.guard(#s.bad==0 and Is(s.t[2],{'Six (slot 6)','#6 Six'},'saved build')
     and (state:find('^captured[;:]')~=nil or state:find('^c:')~=nil) and not claimsActive and Ctx().loadoutSlot==6,
     tag..': the shown cells keep the captured Saved Build Six (slot 6), captured, never active or retargeted',s.detail)
    C.guard(Has(s.tip,{'saved build','six (slot 6)'}) and s.tip:find('shown as captured earlier',1,true)~=nil,
     tag..': the row hover, read once shown, discloses Six (slot 6) as captured',(s.tip:gsub('\n',' / ')))
    Person(tag,s,known)
   end
   Held('captured: opened',true)
   restore[#restore+1]=function() if type(P.Show)=='function' then P.Show() end end
   P.Hide()
   C.setup(NexusEditorFrame:IsVisible(),'captured: the HUD is hidden and the editor stays shown')
   H.Fire('PLAYER_LEAVING_WORLD');Held('captured: leave',false)
   H.Fire('PLAYER_ENTERING_WORLD');Nexus.RefreshHudView();Held('captured: entry and fresh capture',true)
   H.perks.serverActiveSlot=2;H.Notify();A.Poll();H.Advance(1);Held('captured: natural active 2',true)
   WithRev(nil,function() Held('captured: revision missing',true) end)
   Held('captured: revision restored',true)
   Quiet('captured',others,auto)
   C.guard(Writes()==w0 and (Uploads())==u0 and Facts()==facts,'captured: no assignment write, upload or stored assignment change',
    'writes='..Writes()..'/'..w0..' uploads='..(Uploads())..'/'..u0..' '..Facts())
  end)
  for i=#restore,1,-1 do pcall(restore[i]) end
  if not ok then error(err,0) end
 end)
end
-- S6/F2 (destination truth from current facts; fixture only). An empty Echo
-- list proves a known empty Saved Build only when ReadSlots marked its
-- source valid (roleSourceValid, as IsKnownEmptyLoadout requires). For a
-- draft that captured nothing, a selected row whose list is malformed,
-- missing or sparse (projected to no Echoes) is not loaded yet, never the
-- first-run target; so is a native active slot that is not a finite whole
-- number from 0 (math.huge) or a declared maximum below 1 (0). A captured
-- Saved Build keeps its slot and name when its row turns malformed or the
-- native active slot is invalid, but a malformed row is not called empty
-- and gets no refusal. Controls: native 0 with a valid maximum and a valid
-- empty selected row stay the first-run target, a valid populated row is
-- none captured, a valid empty captured row is empty and refused. Real
-- service inputs only (H.perks and the service's GetServerMaxSlots,
-- restored on every exit); each projection with its roleSourceValid and
-- the selected Saved Build are read through the public Slots and
-- SelectedSavedBuild ports. EXPECT: the reproduced defects. GUARD: the
-- controls, the captured identity, no capture or retarget, no effect.
-- SETUP: fixture state. Cells are read as shown (RowCells), the row's own
-- hover only once they are. Offline synthetic only; native NOT RUN.
do
 local ALPHA,ECHO='Alpha',{spellId=201172,quality=0,stacks=1}
 -- Literal full, compact and minimum values of the Saved Build and State
 -- cells, and the hover lines that state the same meaning.
 local WORDS={
  firstRun={label='the first-run target',build={'none in use','none'},
   state={'first-run target (no saved build in use)','first run','1st'},
   tip={'saved build: none in use','state: first-run target (no saved build in use)'}},
  none={label='none captured',build={'none captured','?'},state={'none captured','none'},
   tip={'saved build: none captured','state: none captured'}},
  unknown={label='not loaded yet',build={'not loaded yet','?'},
   state={'saved build data is not loaded yet','not loaded','?'},
   tip={'saved build: not loaded yet','state: saved build data is not loaded yet'}},
 }
 local function OneOf(s,list) for _,v in ipairs(list) do if s==v then return true end end return false end
 -- A shown cell value, plain and lower case, without its full or short label.
 local function Value(text,labels)
  local s=V.Plain(text):lower():gsub('^%s+',''):gsub('%s+$','')
  for _,l in ipairs(labels) do
   local rest=s:match('^'..l..':%s*(.-)$')
   if rest then return rest end
  end
  return s
 end
 -- The editor's destination row as shown, then, only once its four cells
 -- are shown, every line its own hover areas write (OnEnter, then OnLeave).
 local function Read(tag)
  local row=NexusEditorFrame and NexusEditorFrame:IsVisible() and NexusEditorFrame._destinationRow
  if type(row)~='table' or type(row.cells)~='table' then
   C.expect(false,'S6 '..tag..': the editor shows its destination row');return nil
  end
  local t,bad=RowCells(row)
  local lines,n,raised={},0,nil
  if #bad==0 and row:IsVisible() then
   local hits=type(row.hits)=='table' and (rawget(row.hits,'kind') and {row.hits} or row.hits) or {}
   for _,f in pairs(hits) do
    local enter=type(f)=='table' and rawget(f,'kind') and f:IsVisible() and f:GetScript('OnEnter')
    if enter then
     n=n+1
     local got,ok,err=V.TooltipLines(enter,f)
     if not ok then raised=V.printable(err) end
     for _,l in ipairs(got) do lines[#lines+1]=V.Plain(l):lower() end
     local leave=f:GetScript('OnLeave')
     if leave then pcall(leave,f) end
    end
   end
  end
  local tip=table.concat(lines,'\n')
  return {ok=#bad==0 and n>0 and raised==nil,tip=tip,build=Value(t[2],{'saved build','b'}),
   wishlist=Value(t[3],{'wishlist','w'}),state=Value(t[4],{'state','s'}),
   detail=table.concat(t,' | ')..(#bad>0 and (' bad='..table.concat(bad,'; ')) or '')
    ..' || '..(raised or (tip:gsub('\n',' / ')))}
 end
 -- Real service inputs (row 1 beside W-Free, the native active slot and the
 -- declared maximum), then their public projection: row 1 with its Echo
 -- count and roleSourceValid (n nil: no row 1) and the selected Saved Build.
 local function Serve(tag,row1,active,max,sel,n,valid)
  H.service.GetServerMaxSlots=function() return max end
  H.perks.serverBuildSlots={[1]=row1,[107]={name='W-Free',verified=false,echoes=H.Clone(EF)}}
  H.perks.serverActiveSlot=active
  H.Notify();A.Poll();H.Advance(2)
  local s=A.Slots()
  local r=type(s)=='table' and type(s.bySlot)=='table' and s.bySlot[1] or nil
  local got,kept=A.SelectedSavedBuild(s)
  local rowOK=r==nil
  if n~=nil then
   rowOK=type(r)=='table' and type(r.echoes)=='table' and #r.echoes==n and r.roleSourceValid==valid
  end
  local ok=C.setup(type(s)=='table' and s.activeKnown==true and s.activeSlot==active and s.maxSlots==max
   and rowOK and got==sel and kept~=true,
   'S6 '..tag..': fixture: native active '..tostring(active)..', declared maximum '..max..', row 1 '
    ..(n and (n..' projected Echo(es) with roleSourceValid '..tostring(valid)) or 'absent')..', selected '..tostring(sel),
   type(s)=='table' and (tostring(s.activeKnown)..'/'..tostring(s.activeSlot)..'/'..tostring(s.maxSlots)..' row1='
    ..(type(r)=='table' and (tostring(type(r.echoes)=='table' and #r.echoes)..'/'..tostring(r.roleSourceValid)) or 'none')
    ..' selected='..tostring(got)..'/'..tostring(kept)) or 'no slots')
  Nexus.WishlistEditor.Refresh()
  return ok
 end
 -- A draft that captured nothing: the shown Saved Build and State cells,
 -- then the row hover, read want, with no capture cue, no empty Saved Build
 -- and no Alpha.
 local function Current(kind,tag,want)
  local s=Read(tag)
  if not s then return end
  local w=WORDS[want]
  C[kind](s.ok and OneOf(s.build,w.build) and OneOf(s.state,w.state)
   and s.tip:find(w.tip[1],1,true)~=nil and s.tip:find(w.tip[2],1,true)~=nil
   and not s.tip:find('shown as captured earlier',1,true) and not s.tip:find('holds no echoes',1,true)
   and not V.Names(s.tip,ALPHA),
   'S6 '..tag..': the shown Saved Build and State cells, then the row hover, read '..w.label
    ..', with nothing captured, empty or named Alpha',s.detail)
 end
 -- The captured draft: the cells and the hover keep Alpha (slot 1) as
 -- captured (GUARD); its state is empty with a refused Wishlist only when
 -- empty (kind).
 local function Held(kind,tag,empty)
  local s=Read(tag)
  if not s then return end
  local ctx=Ctrl().CreateTargetContext()
  C.guard(s.ok and OneOf(s.build,{'alpha (slot 1)','#1 alpha'}) and s.tip:find('saved build: alpha (slot 1)',1,true)~=nil
   and s.tip:find('shown as captured earlier',1,true)~=nil and type(ctx)=='table' and ctx.loadoutSlot==1
   and ctx.loadoutName==ALPHA and not Ctrl().IsEditing(),
   'S6 '..tag..': the draft keeps its captured Saved Build Alpha (slot 1), shown and disclosed as captured',
   s.detail..' ctx='..(type(ctx)=='table' and (tostring(ctx.loadoutSlot)..'/'..tostring(ctx.loadoutName)) or 'none'))
  local st,wl=s.state,s.wishlist
  local said=st:find('empty',1,true)~=nil or st:find('no echoes',1,true)~=nil or st=='c:0'
  local refused=wl:find('no valid assignment',1,true)~=nil or wl:find('^refused')~=nil or wl=='!'
  local told=s.tip:find('holds no echoes',1,true)~=nil
  C[kind](s.ok and (st:find('^captured')~=nil or st:find('^c:')~=nil) and said==empty and refused==empty and told==empty,
   'S6 '..tag..': the captured state '..(empty and 'is empty and the Wishlist refused' or 'claims no empty Saved Build and no refusal')
    ..', in the cells and the hover',s.detail)
 end
 C.scenario('S6/F2 malformed rows and invalid current facts prove no first-run target or empty Saved Build',function()
  Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
  local realMax=H.service.GetServerMaxSlots
  local ok,err=pcall(function()
   local Ed=Nexus.WishlistEditor
   if not (type(Ed)=='table' and type(Ed.Refresh)=='function' and type(A.Slots)=='function'
    and type(A.SelectedSavedBuild)=='function') then
    C.expect(false,'S6: the public editor Refresh and the Slots and SelectedSavedBuild ports exist');return
   end
   local others,auto,facts=Others(),Auto(),Facts()
   SlashCmdList.NEXUS('editor');H.Advance(1)
   if not C.setup(NexusEditorFrame and NexusEditorFrame:IsShown() and Ctrl().CreateTargetContext()==nil
    and not Ctrl().IsEditing(),'S6: fixture: a new draft begun at native 0 captured no Saved Build') then return end
   local function Row1(echoes) return {name=ALPHA,verified=true,echoes=echoes} end
   if Serve('native 0',nil,0,6,nil) then Current('guard','native 0 with a valid maximum','firstRun') end
   if Serve('valid empty',Row1({}),1,6,1,0,true) then Current('guard','valid empty selected row','firstRun') end
   if Serve('malformed',Row1({{spellId='bad'}}),1,6,1,0,false) then Current('expect','malformed selected row','unknown') end
   if Serve('missing',{name=ALPHA,verified=true},1,6,1,0,false) then
    Current('expect','selected row without an Echo list','unknown')
   end
   if Serve('sparse',Row1({[2]=H.Clone(ECHO)}),1,6,1,0,false) then Current('expect','sparse selected row','unknown') end
   if Serve('infinite native',nil,math.huge,6,nil) then Current('expect','native active slot math.huge','unknown') end
   if Serve('zero maximum',nil,1,0,nil) then Current('expect','native 1 with declared maximum 0','unknown') end
   if Serve('valid populated',Row1({H.Clone(ECHO)}),1,6,1,1,true) then
    Current('guard','valid populated selected row','none')
   end
   C.guard(Ctrl().CreateTargetContext()==nil and not Ctrl().IsEditing(),
    'S6: the uncaptured draft captured and retargeted to no Saved Build')
   -- Reopened through the editor's own Show, the new draft captures the
   -- populated Saved Build selected now.
   Close();SlashCmdList.NEXUS('editor');H.Advance(1)
   local ctx=Ctrl().CreateTargetContext()
   if not C.setup(NexusEditorFrame and NexusEditorFrame:IsShown() and type(ctx)=='table' and ctx.loadoutSlot==1
    and ctx.loadoutName==ALPHA and not Ctrl().IsEditing(),
    'S6 captured: fixture: reopened, the new draft captured the populated Saved Build Alpha (slot 1)',
    type(ctx)=='table' and (tostring(ctx.loadoutSlot)..'/'..tostring(ctx.loadoutName)) or 'none') then return end
   Ed.Refresh();Held('guard','captured populated row',false)
   if Serve('captured malformed',Row1({{spellId='bad'}}),1,6,1,0,false) then
    Held('expect','captured row turned malformed',false)
   end
   if Serve('captured valid empty',Row1({}),1,6,1,0,true) then Held('guard','captured row valid empty',true) end
   if Serve('captured, infinite native',Row1({H.Clone(ECHO)}),math.huge,6,nil,1,true) then
    Held('guard','captured populated row, native active slot math.huge',false)
   end
   Quiet('S6',others,auto)
   C.guard(Writes()==0 and Uploads()==0 and Facts()==facts,'S6: no assignment written and nothing uploaded (unchanged)',Facts())
  end)
  H.service.GetServerMaxSlots=realMax
  pcall(Close)
  if not ok then error(err,0) end
 end)
end
-- F4 (world-session identity of the held observation): the destination
-- row's held observation counts only in the actual world session, which the
-- Panel's read-only DestinationSessionCount returns; the writable public
-- Panel.destinationSessionRevision alone cannot stand in for it. A new
-- draft at active 0 holds the current first-run facts; the HUD is hidden
-- while the editor stays shown. A real PLAYER_LEAVING_WORLD publishes the
-- next revision and no editor refresh runs; only then is that one public
-- scalar rolled back to the held revision, before the first refresh, and it
-- is restored to the published value on every exit. EXPECT: the shown Saved
-- Build and State cells, then the row hover, read not loaded, never the held
-- first-run facts; the accessor gives the actual session as one value and
-- reads or changes nothing. GUARD: accepted behaviour (the restored revision,
-- a real entry and a fresh capture of the same name revive nothing; the next
-- natural cold observation reacquires; warm read profile; no effect).
-- SETUP: fixture state, including the advanced publication, no refresh
-- before the rollback and warm measured refreshes. No private Panel state is
-- read or written. Offline synthetic only; native NOT RUN.
do
 local NOT_LOADED={label='Saved Build data not loaded yet',build={'Not loaded yet','?'},
  state={'Saved Build data is not loaded yet','Not loaded','?'},
  tip={{'saved build','not loaded yet'},{'state','saved build data is not loaded yet'}}}
 local FIRST={label='the first-run target',build={'None in use','None'},
  state={'First-run target (no Saved Build in use)','First run','1st'},
  tip={{'saved build','none in use'},{'state','first-run target (no saved build in use)'}}}
 local NONE={label='no destination captured',build={'None captured','?'},state={'None captured','None'},
  tip={{'saved build','none captured'},{'state','none captured'}}}
 local READS={'slots','selected','loadout','wishlist','backend','active','unit'}
 local function Esc(s) return (tostring(s):lower():gsub('(%p)','%%%1')) end
 -- Shown text (an optional Label: prefix aside) that is one of the literal
 -- alternatives, or one of them cut at its end.
 local function Is(text,alternatives,label)
  local shown=V.Plain(text):lower()
  for _,t in ipairs({shown,label and shown:match('^'..Esc(label)..':%s*(.-)$') or nil}) do
   local stem=t:match('^(.-)%.%.%.$') or t:match('^(.-)\226\128\166$')
   for _,a in ipairs(alternatives) do
    a=a:lower()
    if t==a or (stem and #stem>=3 and #stem<#a and a:sub(1,#stem)==stem) then return true end
   end
  end
  return false
 end
 local function Has(tip,pair) return tip:find(Esc(pair[1])..':?%s*'..Esc(pair[2]))~=nil end
 local function ValidRev(v) return type(v)=='number' and v>=0 and v<math.huge and v==math.floor(v) end
 -- The editor's destination row as shown, then, only while it is shown,
 -- every line its own hover areas disclose (plain, lower case).
 local function Read()
  local row=NexusEditorFrame and NexusEditorFrame._destinationRow
  local s={t={'','','',''},bad={'no destination row'},tip=''}
  if type(row)=='table' and type(row.cells)=='table' then
   s.t,s.bad=RowCells(row)
   local lines={}
   if row:IsVisible() and type(row.hits)=='table' then
    for _,h in ipairs(row.hits) do
     local enter=type(h)=='table' and h:IsVisible() and h:GetScript('OnEnter')
     if enter then
      for _,l in ipairs((V.TooltipLines(function() enter(h) end))) do lines[#lines+1]=V.Plain(l):lower() end
      local leave=h:GetScript('OnLeave');if leave then pcall(leave,h) end
     end
    end
   end
   s.tip=table.concat(lines,'\n')
  end
  s.detail=table.concat(s.t,' | ')..(#s.bad>0 and (' bad='..table.concat(s.bad,'; ')) or '')
  return s
 end
 local function Shows(kind,tag,s,want)
  C[kind](#s.bad==0 and Is(s.t[2],want.build,'saved build') and Is(s.t[4],want.state,'state'),
   tag..': the shown Saved Build and State cells read '..want.label,s.detail)
  C[kind](Has(s.tip,want.tip[1]) and Has(s.tip,want.tip[2]) and not s.tip:find('shown as captured earlier',1,true),
   tag..': the row hover, read once shown, discloses '..want.label..', not captured',(s.tip:gsub('\n',' / ')))
 end
 local function Person(tag,s,known)
  C.guard(#s.bad==0 and Is(s.t[1],known and {CHARACTER} or {'Not known','?'},'character')
   and Has(s.tip,{'character',known and CHARACTER or 'not known'}),
   tag..': the shown character cell and hover read '..(known and CHARACTER or 'not known'),s.detail)
 end

 C.scenario('F4: a real world leave and a public revision rollback before any refresh revive no held facts',function()
  Boot({active=0,slots=World()})
  local P,Ed=Nexus.Panel,Nexus.WishlistEditor
  local slash=SlashCmdList and SlashCmdList.NEXUS
  if not (type(P)=='table' and type(P.Hide)=='function' and type(P.CachedDestinationCharacter)=='function'
   and type(Ed)=='table' and type(Ed.Refresh)=='function' and type(Nexus.RefreshHudView)=='function'
   and type(slash)=='function') then
   C.expect(false,'F4: the public editor, HUD hide, cached character and HUD capture exist');return
  end
  local n,restore={},{}
  -- Counting wrappers of existing public getters, server reads, UnitName and
  -- the editor's public Refresh, each restored on every exit.
  local function Wrap(t,k,key)
   local real=t[k]
   if type(real)~='function' then return end
   n[key]=0
   t[k]=function(...) n[key]=n[key]+1;return real(...) end
   restore[#restore+1]=function() t[k]=real end
  end
  local function Reads() return (n.slots or 0)+(n.selected or 0)+(n.backend or 0)+(n.active or 0) end
  local function Refresh(tag)
   local r0=Reads()
   Ed.Refresh()
   C.setup(Reads()==r0 and NexusEditorFrame:IsVisible(),
    tag..': the editor stays shown and this refresh is warm (no Slots, selected or server slot read)',Reads()-r0)
   return Read()
  end
  local ok,err=pcall(function()
   slash('editor');Nexus.RefreshHudView();Ed.Refresh()
   local found,ctl=pcall(Ctrl)
   if not found then C.expect(false,'F4: the editor controller is reachable',ctl);return end
   local function Uncaptured()
    local c,t=Ctx(),type(ctl.CreateTargetContext)=='function' and ctl.CreateTargetContext() or nil
    return c.loadoutSlot==nil and c.name==nil and not (type(t)=='table' and tonumber(t.loadoutSlot))
   end
   C.setup(NexusEditorFrame and NexusEditorFrame:IsVisible() and Uncaptured(),
    'F4: fixture: a new draft is open at active 0 and captured no destination')
   local row=NexusEditorFrame and NexusEditorFrame._destinationRow
   if type(row)~='table' or type(row.cells)~='table' then
    C.expect(false,'F4: the editor shows its destination row');return
   end
   for _,w in ipairs({{A,'Slots','slots'},{A,'SelectedSavedBuild','selected'},{A,'GetLoadoutWishlist','loadout'},
    {A,'Wishlist','wishlist'},{A,'Level','level'},{H.service,'GetServerBuildSlots','backend'},
    {H.service,'GetServerActiveSlot','active'},{_G,'UnitName','unit'},{Ed,'Refresh','refresh'}}) do Wrap(w[1],w[2],w[3]) end
   local s=Read()
   local token=P.destinationSessionRevision
   C.setup(ValidRev(token) and #s.bad==0 and Is(s.t[1],{CHARACTER},'character')
    and Is(s.t[2],FIRST.build,'saved build') and Is(s.t[4],FIRST.state,'state'),
    'F4: fixture: the row holds the current first-run facts and '..CHARACTER..' at a valid revision',tostring(token)..' '..s.detail)
   local others,w0,u0,auto,facts=Others(),Writes(),(Uploads()),Auto(),Facts()
   restore[#restore+1]=function() if type(P.Show)=='function' then P.Show() end end
   P.Hide()
   C.setup(NexusEditorFrame:IsVisible(),'F4: fixture: the HUD is hidden and the editor stays shown')
   local f0=n.refresh or 0
   H.Fire('PLAYER_LEAVING_WORLD')
   local left=P.destinationSessionRevision
   s=Read()
   local advanced=ValidRev(token) and ValidRev(left) and left==token+1
   C.setup(advanced and (n.refresh or 0)==f0 and #s.bad==0 and Is(s.t[1],{CHARACTER},'character')
    and Is(s.t[4],FIRST.state,'state'),
    'F4: fixture: the real leave published the next revision and no editor refresh or row update ran since',
    tostring(token)..' -> '..tostring(left)..' refreshes='..((n.refresh or 0)-f0)..' '..s.detail)
   if not advanced then return end
   -- Only the public scalar is rolled back, to the held revision, before the
   -- first refresh; the published value is restored on every exit.
   P.destinationSessionRevision=token
   local done,why=pcall(function()
    local get=P.DestinationSessionCount
    if C.expect(type(get)=='function','F4: the Panel offers its read-only world-session accessor') then
     local n0={}
     for k,v in pairs(n) do n0[k]=v end
     local count,value=select('#',get()),get()
     local idle=true
     for k,v in pairs(n) do if v~=n0[k] then idle=false end end
     C.expect(count==1 and value==left and rawequal(P.destinationSessionRevision,token) and idle,
      'F4: the accessor gives the actual session as one value while the public scalar is rolled back; it reads and changes nothing',
      tostring(value)..' values='..count..' public='..tostring(P.destinationSessionRevision)..' idle='..tostring(idle))
    end
    s=Refresh('F4 rollback')
    Shows('expect','F4 rollback before the first refresh',s,NOT_LOADED)
    Person('F4 rollback before the first refresh',s,false)
    C.guard(Uncaptured(),'F4 rollback: the draft adopted no Saved Build',Ctx().loadoutSlot)
   end)
   P.destinationSessionRevision=left
   if not done then error(why,0) end
   s=Refresh('F4 restored revision')
   Shows('guard','F4 restored revision alone',s,NOT_LOADED);Person('F4 restored revision alone',s,false)
   H.Fire('PLAYER_ENTERING_WORLD')
   local entered,u=P.destinationSessionRevision,n.unit or 0
   Nexus.RefreshHudView()
   local cached=P.CachedDestinationCharacter()
   C.setup(ValidRev(entered) and entered>left and (n.unit or 0)>u and cached==CHARACTER,
    'F4: fixture: a real entry published a newer revision and Main freshly captured the same name',
    tostring(left)..' -> '..tostring(entered)..' '..tostring(cached))
   s=Refresh('F4 entry and fresh capture')
   Shows('guard','F4 entry and a fresh capture of the same name',s,NOT_LOADED)
   Person('F4 entry and a fresh capture of the same name',s,true)
   local r0=Reads()
   H.perks.serverActiveSlot=1;H.Notify();A.Poll();H.Advance(1);Ed.Refresh()
   C.setup(Reads()>r0,'F4: the natural server revision to active 1 made its existing cold reads',Reads()-r0)
   s=Read()
   Shows('guard','F4 next natural cold observation',s,NONE);Person('F4 next natural cold observation',s,true)
   C.guard(Uncaptured(),'F4: the draft adopted no Saved Build',Ctx().loadoutSlot)
   local held,n0=table.concat(s.t,'|'),{}
   for k,v in pairs(n) do n0[k]=v end
   for _=1,5 do Ed.Refresh() end
   local level=(n.level or 0)-(n0.level or 0)
   local idle,profile=level==5,{'level='..level}
   for _,k in ipairs(READS) do
    local d=(n[k] or 0)-(n0[k] or 0)
    profile[#profile+1]=k..'='..d
    if d~=0 then idle=false end
   end
   C.guard(idle and held==table.concat(Read().t,'|'),
    'F4 quiet: five warm refreshes read Level 5 times and no Slots, selected, Wishlist, server slot or UnitName; the row holds still',
    table.concat(profile,' '))
   Quiet('F4',others,auto)
   C.guard(Writes()==w0 and (Uploads())==u0 and Facts()==facts,'F4: no assignment write, upload or stored assignment change',
    'writes='..Writes()..'/'..w0..' uploads='..(Uploads())..'/'..u0..' '..Facts())
  end)
  for i=#restore,1,-1 do pcall(restore[i]) end
  local closed,closeErr=pcall(Close)
  if not ok then error(err,0) end
  if not closed then error(closeErr,0) end
 end)
end
C.finish('(confirmations name the captured destination; first-run labelled; no guessed destination)')
