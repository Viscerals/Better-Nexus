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

C.scenario('the HUD destination row fits an empty long-named Saved Build 123 at the 2.0 font scale',function()
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 G.UseFont(G.MODELS.double)
 local ok,res=pcall(Nexus.Panel.Render,{character=CHARACTER,
  progress={activeSlot=123,activeSlotName='Long \195\169cho | field '..string.rep('wide ',12),wishlistName='W-Free',
   owned=0,total=2,missing={},shed={},unknownTomes={},toLock={},isCommunityPreview=false},
  assignment={state='ready',name='W-Free',emptySlot=true},cards={},auto=false,level=40})
 C.setup(ok and res~=false,'R-HUD: fixture: the real HUD renders the synthetic model',res)
 local row=_G.NexusPanel and NexusPanel._destinationRow
 local has=type(row)=='table' and type(row.cells)=='table'
 C.expect(has,'R-HUD: the HUD shows its destination row of cells')
 if not (ok and has) then return end
 local t,bad=RowCells(row)
 local all=table.concat(t,' / ')
 print('OBSERVED','R-HUD row='..all)
 C.expect(#bad==0,'R-HUD: before hover, four visible cells, each within its own width, disjoint inside the row',table.concat(bad,'; '))
 local who=t[1]:gsub('^Character:%s*',''):gsub('^C:%s*',''):gsub('%.%.%.$','')
 C.expect(who~='' and CHARACTER:sub(1,#who)==who
  and ((t[2]:find('#123',1,true) and not t[2]:find('#123%d')) or t[2]:find('slot 123)',1,true))
  and (t[3]:find('!$') or t[3]:find('Refused',1,true) or t[3]:find('No valid assignment',1,true) or t[3]:find('W-F',1,true))
  and V.Names(t[4],'Empty'),
  'R-HUD: it shows the leading character, the whole #123, the whole Wishlist refusal marker (or W-Free) and the whole Empty state',all)
 local hit=type(row.hits)=='table' and row.hits[2] or nil
 local enter=hit and hit:GetScript('OnEnter')
 local tip=enter and V.Plain(table.concat(V.TooltipLines(function() enter(hit) end),' / ')) or ''
 C.expect(tip:find('Character: '..CHARACTER,1,true) and tip:find('slot 123)',1,true)
  and tip:find(string.rep('wide ',11)..'wide',1,true) and tip:find('holds no Echoes',1,true),
  'R-HUD: hovering the Saved Build cell then discloses the whole destination',tip)
end)

C.finish('(confirmations name the captured destination; first-run labelled; no guessed destination)')
