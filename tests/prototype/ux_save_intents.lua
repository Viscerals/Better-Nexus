-- M3 (UX-03 save intents; M1 F1/C3, F6, F7/C1; M2 N1/N2; PRIORITY N1/N3/N5/N7/N13):
-- a new plan with a captured destination can be saved with or without its
-- assignment (Save & assign through Create & assign, Save changes through
-- Create unassigned), each a controller intent bound into its confirmation;
-- an opened plan keeps its own assignment (Save changes), and one opened for a
-- Saved Build that does not hold it offers Save & assign beside Save changes;
-- an explicit Save changes never writes a destination the plan did not have
-- (no new slot-1 handoff, no assignment); the destination a confirmation
-- named is the only one a save may write (a changed first-run/none decision
-- uploads nothing); a host error or an error raised during the upload is
-- recorded as unconfirmed and never repeated; an upload whose assignment or
-- local write fails reports a truthful partial with a safe next step; a save
-- kept only for this session says so; an owner change, Unassign, Restore and
-- the automatic promotion retire an earlier result for good.
-- Categories (view_regression_support): EXPECT is behaviour added in M3 (it
-- fails on the accepted predecessor ea3268a8); GUARD is behaviour that already
-- holds there and must keep holding; SETUP is the fixture. The oracles are the
-- host upload call (H.actions 'upload'; server slot 0 is Create), the
-- assignment writers (counted at the adapter boundary), the Store and the
-- editor's own result row, never a DTO alone.
-- Real TOC boot, adapter, controller, editor controls and the editor's own
-- StaticPopup handlers; synthetic host services and saved data only. The
-- harness does not model the native 3.3.5 StaticPopup; no native claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_save_intents')
local H,A,writes,spends
-- Revision 6 (updated-client compatibility, full-CI finding): GameAdapter.
-- UploadWishlist replaces an existing server Wishlist (slot > 0) only when
-- the current slot list shows that destination in full; a missing one is
-- refused ("stale_slot") and starts no spacing. Slot 103 is not in this
-- fixture's list, so the spacing setup names it as a known synthetic Wishlist
-- mirror (above the declared slots, unverified, the spacer's own Echoes) for
-- that one real upload and then puts the list back exactly as it was. The
-- spacing window is the production one, opened by that real upload; nothing
-- is stubbed and no timestamp is set.
local function KnownSlotUpload(upload,slot,name,echoes)
 local created=H.perks.serverBuildSlots==nil
 if created then H.perks.serverBuildSlots={} end
 local slots=H.perks.serverBuildSlots
 local prior=slots[slot]
 local rows={}
 for i,e in ipairs(echoes) do rows[i]={spellId=e.spellId,quality=e.quality,stacks=e.stacks or 1,locked=false} end
 slots[slot]={name=name,verified=false,echoes=rows}
 local ok,why=upload(slot,name,echoes)
 slots[slot]=prior
 if created then H.perks.serverBuildSlots=nil end
 return ok,why
end
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local E3={{spellId=201176,quality=0,stacks=1}}
local E6={{spellId=201173,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}

local function World(extra)
 local slots={[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [3]={name='Arena',verified=true,echoes=E3},[6]={name='Six',verified=true,echoes=E6},
  [106]={name='W-Six',verified=false,echoes=E6},[107]={name='W-Free',verified=false,echoes=EF}}
 for k,v in pairs(extra or {}) do slots[k]=v end
 return slots
end

local function Boot(o)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;EchoJournalMicroButton=nil
 NexusEditorFrame=nil;NexusWishlistNameInput=nil;NexusWishlistEditorSwitchButton=nil
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusWishlistAssignNowButton=nil
 NexusWishlistEditorLoadoutMenu=nil;NexusWishlistSaveOnlyButton=nil;NexusLoadoutAssociationPanel=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201173,'Echo Six',0,5);H.AddEcho(201174,'Echo Free',0,5)
 H.AddEcho(201175,'Echo Fire',0,5);H.AddEcho(201176,'Echo Arena',0,5);H.AddEcho(201177,'Echo Four',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots=H.Clone(o.slots)
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
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
end
-- The editor's own controller (no public handle), for fixture reads only.
local function Ctrl()
 local show=Nexus.WishlistEditor.Show
 for i=1,255 do local n,v=debug.getupvalue(show,i);if not n then break end
  if n=='wishlistController' then return v end end
 error('editor controller not found')
end
local function Visible(f) return f and f:IsVisible() end
-- A visible button of the editor with this exact label (colour codes ignored).
-- The editor's primary action is named by its effect: a legacy label also
-- finds the action with that default intent (new label first, then legacy),
-- so the same scenario runs on the predecessor.
local LABELS={['Create Wishlist']={'Create & assign','Create unassigned','Create Wishlist'},
 ['Save Wishlist']={'Save & assign','Save changes','Save Wishlist'}}
local function EditorButton(text)
 for _,label in ipairs(LABELS[text] or {text}) do
  for _,f in ipairs(H.frames) do
   if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame and V.Plain(f:GetText() or '')==label then return f end
  end
 end
 return nil
end
-- The editor's Create/Save control, whatever it reads now (created before the
-- Save changes alternative beside it, so it is the first match).
local APPLY_LABELS={['Create Wishlist']=true,['Save Wishlist']=true,['Saved']=true,['Saving...']=true,
 ['Create & assign']=true,['Create unassigned']=true,['Save & assign']=true,['Save changes']=true}
local function ApplyButton()
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame then
   local t=V.Plain(f:GetText() or '')
   if APPLY_LABELS[t] then return f end
  end
 end
 return nil
end
-- The plain label of a visible editor control, or nil.
local function Label(f) return f and V.Plain(f:GetText() or '') or nil end
-- Every visible editor button label, sorted and joined (for messages).
local function EditorLabels()
 local t={}
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame then t[#t+1]=V.Plain(f:GetText() or '') end
 end
 table.sort(t)
 return table.concat(t,'|')
end
local function ClickCatalog(id)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==id then f:Click();return true end end
 error('visible catalog row absent: '..id)
end
local function selected(id)
 for _,f in ipairs(H.frames)do if f:IsVisible() and f.plus and f.data and f.data.spellId==id then return f end end
 error('visible selected row absent: '..id)
end
local function Name(text) NexusWishlistNameInput:SetText(text) end
local function NameText()
 local box=NexusWishlistNameInput
 if not box then return nil end
 if box._NexusRawText then return box:_NexusRawText() end
 return box:GetText()
end
-- One click; the confirmation that click opened, or nil.
local function Click(button)
 if not button then return nil end
 local before=H.popup
 button:Click()
 if H.popup~=nil and H.popup~=before then return H.popup end
 return nil
end
-- The client runs a dialog's OnAccept and hides it; the harness keeps H.popup.
local function Accept(p)
 if not p then return nil end
 if H.popup==p then H.popup=nil end
 return StaticPopupDialogs[p.which].OnAccept(p.frame,p.data)
end
local function Cancel(p)
 if not p then return end
 if H.popup==p then H.popup=nil end
 StaticPopupDialogs[p.which].OnCancel(p.frame,p.data)
end
-- The confirmation as the client shows it (text with the show arguments).
local function Asked(p)
 if not p then return nil end
 local d=StaticPopupDialogs[p.which] or {}
 local ok,s=pcall(string.format,tostring(d.text or ''),p.arg1,p.arg2)
 return V.Plain(ok and s or tostring(d.text or ''))
end
local function Uploads(slot)
 local n=0
 for _,a in ipairs(H.actions) do if a[1]=='upload' and (slot==nil or a[2]==slot) then n=n+1 end end
 return n
end
local function Creates() return Uploads(0) end
local function LastCreate()
 local last
 for _,a in ipairs(H.actions) do if a[1]=='upload' and a[2]==0 then last=a end end
 return last
end
local function Others() local n=0;for _,a in ipairs(H.actions) do if a[1]~='upload' then n=n+1 end end;return n end
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
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return V.Plain(table.concat(heard,' / '))
end
-- The editor's result row (its one visible line), or nil.
local function ResultRow()
 if not NexusEditorFrame then return nil end
 for _,r in ipairs(NexusEditorFrame.regions) do
  if r.kind=='FontString' and r:IsVisible() then
   local t=V.Plain(r:GetText() or '')
   if t:find('^Saved') or t:find('^Uploaded') or t:find('^Not saved') or t:find('^Not confirmed') then return t,r end
  end
 end
 return nil
end
-- Every hover line of the result row, joined.
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
-- The controller's current result for what the name field holds (a read).
local function Result()
 local c=Ctrl()
 return c.SaveResult and c.SaveResult(NameText()) or nil
end
local function Describe(r)
 if type(r)~='table' then return tostring(r) end
 return tostring(r.kind)..'/'..tostring(r.reason)..'/'..tostring(r.intent)..'/'..tostring(r.sessionOnly)
end
local function AssignNowButton()
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame
   and V.Plain(f:GetText() or ''):find('^Assign now') then return f end
 end
 return nil
end
-- The server lists an upload in a designed slot (a Create uploads to 0).
local function MirrorAt(slot,last)
 local rows=H.Clone(H.perks.serverBuildSlots or {});rows[slot]={name=last[3],verified=false,echoes=H.Clone(last[4])}
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll();H.Advance(4)
end
local function SetRows(change,active)
 local rows=H.Clone(H.perks.serverBuildSlots or {})
 for k,v in pairs(change) do rows[k]=v end
 H.perks.serverBuildSlots=rows
 if active~=nil then H.perks.serverActiveSlot=active end
 H.Notify();A.Poll();H.Advance(1)
end
-- A new draft in the editor as the player opens it, with one Echo.
local function NewDraft(name,id)
 SlashCmdList.NEXUS('editor')
 Name(name);ClickCatalog(id or 201175)
 Nexus.WishlistEditor.Refresh()
end

C.scenario('I1 Create unassigned: Save changes of a new plan with a captured destination assigns nothing',function()
 Boot({active=2,slots=World()})
 NewDraft('Plain plan')
 local c=Ctrl()
 C.setup(c.CreateTargetContext() and c.CreateTargetContext().loadoutSlot==2,'I1: fixture: the new draft captured Saved Build 2 (Fire PvE)')
 C.expect(c.DefaultIntent and c.DefaultIntent()=='saveAndAssign' and c.SaveAndAssignTarget
  and (c.SaveAndAssignTarget() or {}).slot==2,
  'I1: the controller names the default intent (Save & assign) and the captured destination it writes')
 local w,facts,others,auto=Writes(),Facts(),Others(),Auto()
 local only=EditorButton('Create unassigned')
 C.expect(only~=nil and ApplyButton()~=nil,'I1: a new plan with a captured destination offers Create unassigned beside Create Wishlist')
 C.guard(Writes()==w and Creates()==0,'I1: reading the intent and drawing the controls upload and write nothing')
 local p=Click(only)
 local asked=Asked(p)
 print('OBSERVED','I1 confirmation='..tostring(asked))
 C.expect(asked~=nil and asked:find('saved without an assignment',1,true)~=nil and V.Names(asked,'Fire PvE')
  and not asked:find('After a successful save it is assigned',1,true) and not asked:find('Auto is ON',1,true),
  'I1: its confirmation says it is saved without an assignment and that Fire PvE keeps its choice',asked)
 C.expect(p~=nil and type(p.data)=='table' and type(p.data.confirmation)=='table'
  and p.data.confirmation.intent=='saveChanges','I1: the Save changes intent is bound into that confirmation')
 Accept(p)
 C.expect(Creates()==1 and Writes()==w and Facts()==facts,'I1: Create unassigned uploads once and writes no assignment',Facts())
 local row=ResultRow()
 C.expect(row~=nil and row:find('saved without an assignment, as you chose',1,true)~=nil,
  'I1: the result row says it was saved unassigned, as chosen',row)
 local r=Result()
 C.expect(r~=nil and r.kind=='unassigned' and r.reason=='saveOnly' and r.intent=='saveChanges' and r.assignNow==true,
  'I1: the result names the intent and offers Assign now',Describe(r))
 C.guard(Others()==others and spends==0 and Auto()==auto,'I1: no other game action, spend or Auto change')
end)

C.scenario('I2 Create Wishlist is Save & assign to the captured destination; legacy and refused intents',function()
 Boot({active=2,slots=World()})
 NewDraft('Assigned plan')
 local p=Click(ApplyButton())
 local asked=Asked(p)
 C.setup(p~=nil,'I2: fixture: Create Wishlist asks for confirmation')
 C.guard(asked~=nil and asked:find('After a successful save it is assigned to',1,true)~=nil and V.Names(asked,'Fire PvE')
  and asked:find('captured',1,true)~=nil,'I2: the confirmation names the captured destination it assigns',asked)
 C.expect(p~=nil and type(p.data)=='table' and p.data.intent=='saveAndAssign' and type(p.data.confirmation)=='table'
  and p.data.confirmation.intent=='saveAndAssign' and p.data.confirmation.destinationKey=='savedBuild:2',
  'I2: the confirmation binds Save & assign and the destination it names')
 Accept(p)
 C.guard(Creates()==1 and writes.SetLoadoutWishlistIdentity==1 and Stored(2)~=nil and Stored(2).name=='Assigned plan'
  and Stored(3)==nil,'I2: it uploads once and assigns exactly the named Saved Build',Facts())
 local r=Result()
 C.expect(r~=nil and r.kind=='assigned' and r.intent=='saveAndAssign','I2: the result names the intent',Describe(r))
 -- The direct payload API (no confirmation, no displayed destination) keeps
 -- its earlier meaning: the draft's captured destination.
 H.Advance(4)
 Nexus.WishlistEditor.NewWishlist()
 local ok=Ctrl().AcceptApply(0,'Direct plan',H.Clone(E3))
 C.guard(ok==true and Creates()==2 and writes.SetLoadoutWishlistIdentity==2 and Stored(2)~=nil
  and Stored(2).name=='Direct plan','I2: the direct payload API still saves to the captured destination',Facts())
 -- Save & assign without a captured destination, and an unknown intent, are
 -- refused before anything is offered.
 Boot({active=1,slots=World()})
 local opened=Nexus.WishlistEditor.OpenForCandidate({title='Copied plan',echoes=H.Clone(EF)})
 local c=Ctrl()
 C.setup(opened and c.CreateTargetContext()==nil,'I2: fixture: a copied draft with no captured destination')
 local data,mode=c.PrepareApply('Copied plan','saveAndAssign')
 C.expect(data==nil and mode=='no_destination','I2: Save & assign is refused when no destination was captured',tostring(mode))
 if data then c.CancelApply(data) end
 data,mode=c.PrepareApply('Copied plan','bogus')
 C.expect(data==nil and mode=='invalid_intent','I2: an unknown intent is refused',tostring(mode))
 if data then c.CancelApply(data) end
 C.guard(Creates()==0 and Writes()==0,'I2: these refusals upload and assign nothing')
end)

C.scenario('I3 an opened plan: Save changes keeps its own assignment; no assignment choice',function()
 Boot({active=6,slots=World()})
 local ok,why=A.SetLoadoutWishlistIdentity(6,'W-Six',H.Clone(E6));writes.SetLoadoutWishlistIdentity=0
 C.setup(ok,'I3: fixture: Saved Build 6 is assigned W-Six',why)
 H.Notify();A.Poll();H.Advance(1)
 for _,cand in ipairs(A.GetWishlistCandidates()) do if cand.slot==106 then Nexus.WishlistEditor.OpenForWishlist(cand,6) end end
 local c=Ctrl()
 local ctx=c.EditingContext() or {}
 C.setup(ctx.name=='W-Six' and ctx.loadoutSlot==6,'I3: fixture: W-Six is open for Saved Build 6',ctx.name)
 C.expect(c.DefaultIntent and c.DefaultIntent()=='saveChanges' and c.SaveAndAssignTarget and c.SaveAndAssignTarget()==nil,
  'I3: an opened plan defaults to Save changes and has no Save & assign target')
 selected(201173).plus:Click()
 Nexus.WishlistEditor.Refresh()
 C.guard(EditorButton('Create unassigned')==nil,'I3: no Create unassigned control for an opened plan')
 local p=Click(ApplyButton())
 C.setup(p~=nil and p.which=='WISHLISTREALIZER_UPDATE_WISHLIST','I3: fixture: Save asks for confirmation')
 Accept(p)
 C.guard(Uploads(106)==1 and writes.UpdateWishlistAssociationAfterSave==1 and Stored(6)~=nil and Stored(6).name=='W-Six',
  'I3: Save uploads W-Six to its own server slot and keeps Saved Build 6 on the same plan',Facts())
 local r=Result()
 C.expect(r~=nil and r.intent=='saveChanges' and r.kind=='assigned','I3: the result names Save changes',Describe(r))
end)

C.scenario('I4 F6: a confirmed first-run save whose destination changed uploads nothing',function()
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 NewDraft('First plan',201174)
 local c=Ctrl()
 C.setup(c.CreateTargetContext()==nil and not c.IsEditing(),'I4: fixture: a new first-run draft')
 local p=Click(ApplyButton())
 local asked=Asked(p)
 C.setup(asked~=nil and asked:find('first-run target',1,true)~=nil,'I4: fixture: the confirmation names the first-run target',asked)
 -- Before the accept, Saved Build One appears and becomes active.
 SetRows({[1]={name='One',verified=true,echoes=H.Clone(E1)}},1)
 local facts,w=Facts(),Writes()
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','I4 creates='..Creates()..' facts='..Facts())
 C.expect(Creates()==0 and Writes()==w and Facts()==facts,
  'I4: the save is not redirected: nothing is uploaded or assigned',Facts())
 C.expect(said:find('destination named in the confirmation',1,true)~=nil,'I4: it says the confirmed destination changed',said)
 local row=ResultRow()
 C.expect(row~=nil and row:find('^Not saved')~=nil and row:find('destination named in the confirmation',1,true)~=nil,
  'I4: the result says why nothing was saved',row)
end)

C.scenario('I4b F6: a save confirmed without a destination never becomes a first-run assignment',function()
 Boot({active=1,slots=World()})
 local opened=Nexus.WishlistEditor.OpenForCandidate({title='Copied plan',echoes=H.Clone(EF)})
 C.setup(opened and Ctrl().CreateTargetContext()==nil,'I4b: fixture: a copied draft while Saved Build One is selected')
 Nexus.WishlistEditor.Refresh()
 local p=Click(EditorButton('Create Wishlist'))
 local asked=Asked(p)
 C.setup(asked~=nil and asked:find('did not capture a Saved Build',1,true)~=nil,'I4b: fixture: the confirmation names no destination',asked)
 -- Saved Build One empties before the accept (the first-run rule would now apply).
 SetRows({[1]={name='One',verified=true,echoes={}}})
 local facts=Facts()
 Accept(p)
 print('OBSERVED','I4b creates='..Creates()..' facts='..Facts())
 C.expect(Creates()==0 and Facts()==facts and not Stored('first'),
  'I4b: it is not turned into a first-run assignment (nothing uploaded or assigned)',Facts())
end)

C.scenario('I5 PRIORITY.N5: a used confirmation replayed after a successful Create keeps that result',function()
 Boot({active=2,slots=World()})
 NewDraft('Replayed plan')
 local p=Click(ApplyButton())
 C.setup(p~=nil,'I5: fixture: Create asks for confirmation')
 Accept(p)
 C.setup(Creates()==1 and Stored(2)~=nil and Stored(2).name=='Replayed plan','I5: fixture: the Create is saved and assigned',Facts())
 local said=Heard(function() StaticPopupDialogs[p.which].OnAccept(p.frame,p.data) end)
 local r=Result()
 C.guard(Creates()==1 and writes.SetLoadoutWishlistIdentity==1,'I5: the replayed accept sends and assigns nothing')
 C.expect(r~=nil and r.kind=='assigned','I5: the successful result is not replaced by a refusal',Describe(r))
 C.expect(said:find('already used',1,true)~=nil,'I5: the replay says the confirmation was already used',said)
end)

C.scenario('I6 PRIORITY.N3: a refused open keeps the sent draft and its captured destination',function()
 Boot({active=2,slots=World()})
 NewDraft('Kept plan')
 local p=Click(ApplyButton())
 C.setup(p~=nil,'I6: fixture: Create asks for confirmation')
 Accept(p)
 C.setup(Creates()==1,'I6: fixture: the Create uploaded once',Creates())
 H.Advance(4)
 local c=Ctrl()
 local opened=c.BeginWishlist({name='Broken'})
 C.setup(opened==false,'I6: fixture: the open is refused (no Echo list)')
 C.expect(c.CreateTargetContext()~=nil and c.CreateTargetContext().loadoutSlot==2,
  'I6: the refused open keeps the draft\'s captured Saved Build')
 local again=Click(ApplyButton())
 if again then Accept(again) end
 H.Advance(4)
 print('OBSERVED','I6 creates='..Creates()..' offered='..tostring(again~=nil))
 C.expect(again==nil and Creates()==1,'I6: pressing Create again sends nothing (no copy-named second Wishlist)',Creates())
end)

C.scenario('I7 PRIORITY.N1: a host error during the upload is unconfirmed and never repeated',function()
 Boot({active=2,slots=World()})
 NewDraft('Erring plan')
 local upload=H.service.UploadServerBuildSlot
 H.service.UploadServerBuildSlot=function(...) upload(...);error('synthetic host failure after sending') end
 local p=Click(ApplyButton())
 C.setup(p~=nil,'I7: fixture: Create asks for confirmation')
 local said=Heard(function() Accept(p) end)
 H.service.UploadServerBuildSlot=upload
 C.setup(Creates()==1,'I7: fixture: the host recorded the upload before it raised',Creates())
 C.guard(Writes()==0,'I7: nothing is assigned after an unconfirmed upload')
 local row=ResultRow()
 C.expect(row~=nil and row:find('^Not confirmed')~=nil,'I7: the result says the upload is not confirmed',row)
 C.expect(said:find('may or may not have reached the server',1,true)~=nil,'I7: the chat says the outcome is unknown',said)
 H.Advance(4)
 local again
 said=Heard(function() again=Click(ApplyButton());if again then Accept(again) end end)
 H.Advance(4)
 print('OBSERVED','I7 creates='..Creates()..' offered='..tostring(again~=nil))
 C.expect(again==nil and Creates()==1,'I7: pressing Create again sends nothing more',Creates())
 C.expect(said:find('may already have been sent',1,true)~=nil,'I7: and says it may already have been sent',said)
 -- A genuine refusal (the host returns false) sends nothing and stays retryable.
 Boot({active=2,slots=World()})
 NewDraft('Refused plan')
 upload=H.service.UploadServerBuildSlot
 H.service.UploadServerBuildSlot=function() return false end
 p=Click(ApplyButton());Accept(p)
 H.service.UploadServerBuildSlot=upload
 C.guard(Creates()==0 and Writes()==0,'I7: a refused upload sends and assigns nothing')
 H.Advance(4)
 again=Click(ApplyButton())
 C.guard(again~=nil,'I7: after a genuine refusal, Create is offered again')
 Cancel(again)
end)

C.scenario('I8 PRIORITY.N13/N7: an error raised out of the upload call is unconfirmed and keeps its stack',function()
 Boot({active=2,slots=World()})
 NewDraft('Raising plan')
 local real=A.UploadWishlist
 A.UploadWishlist=function() error('synthetic adapter failure') end
 local p=Click(ApplyButton())
 C.setup(p~=nil,'I8: fixture: Create asks for confirmation')
 local ok,err=pcall(Accept,p)
 A.UploadWishlist=real
 C.setup(not ok,'I8: fixture: the accept raised the adapter error',err)
 C.guard(Creates()==0 and Writes()==0,'I8: nothing was uploaded or assigned')
 C.expect(type(err)=='string' and err:find('synthetic adapter failure',1,true)~=nil and err:find('traceback',1,true)~=nil,
  'I8: the error is raised again with its message and its stack',err)
 local r=Result()
 C.expect(r~=nil and r.kind=='uncertain','I8: the result says the outcome is not confirmed (fail-closed, never "created")',Describe(r))
end)

C.scenario('I9 F7/C1: a refused assignment after the upload is a truthful partial; never uploaded again',function()
 -- (a) The writer refuses with a reason after the real upload.
 Boot({active=2,slots=World()})
 NewDraft('Partial plan')
 local real=A.SetLoadoutWishlistIdentity
 A.SetLoadoutWishlistIdentity=function(...) writes.SetLoadoutWishlistIdentity=writes.SetLoadoutWishlistIdentity+1;return false,'store unavailable' end
 local p=Click(ApplyButton())
 C.setup(p~=nil,'I9: fixture: Create asks for confirmation')
 Accept(p)
 A.SetLoadoutWishlistIdentity=real
 C.guard(Creates()==1 and writes.SetLoadoutWishlistIdentity==1 and Writes()==1,'I9: one upload, one refused writer call, no other writer',Writes())
 local row=ResultRow()
 C.guard(row~=nil and row:find('^Uploaded')~=nil and row:find('could not be stored right now',1,true)~=nil
  and not row:find('Assigned to',1,true),'I9: the row says uploaded, not assigned, and why',row)
 local hover=ResultHover() or ''
 C.expect(hover:find('does not upload this draft again',1,true)~=nil,'I9: its hover names the safe next step (no second upload)',hover)
 local u,w=Creates(),Writes()
 local assign=AssignNowButton()
 if assign then assign:Click() end
 C.guard(Creates()==u and Writes()==w,'I9: Assign now uploads and writes nothing')
 H.Advance(4)
 local again=Click(ApplyButton());if again then Accept(again) end
 C.guard(Creates()==1,'I9: pressing Create again uploads nothing',Creates())
 -- (b) A bare false: the chat names no guessed reason.
 Boot({active=2,slots=World()})
 NewDraft('Bare plan')
 real=A.SetLoadoutWishlistIdentity
 A.SetLoadoutWishlistIdentity=function(...) writes.SetLoadoutWishlistIdentity=writes.SetLoadoutWishlistIdentity+1;return false end
 p=Click(ApplyButton())
 local said=Heard(function() Accept(p) end)
 A.SetLoadoutWishlistIdentity=real
 row=ResultRow()
 C.guard(row~=nil and row:find('the assignment was refused',1,true)~=nil,'I9b: a writer without a reason is shown neutrally',row)
 C.expect(said:find('assignment failed',1,true)~=nil and not said:find('(unavailable)',1,true),
  'I9b: the chat does not invent "(unavailable)" for a writer that gave no reason',said)
end)

C.scenario('I9c C1: a failed design commit after the upload is a localTargets partial with a safe next step',function()
 Boot({active=2,slots=World()})
 NewDraft('Local plan')
 local owner=Nexus.MainInternals and Nexus.MainInternals.StoreAuthorityOwner
 C.setup(type(owner)=='table' and type(owner.UpdateStateV1)=='function','I9c: fixture: the Store owner exposes UpdateStateV1')
 local realUpdate=owner and owner.UpdateStateV1
 local upload=H.service.UploadServerBuildSlot
 H.service.UploadServerBuildSlot=function(...)
  local r=upload(...)
  -- From the real upload on, the owner reports that it could not write.
  if owner then owner.UpdateStateV1=function() return nil end end
  return r
 end
 local p=Click(ApplyButton())
 C.setup(p~=nil,'I9c: fixture: Create asks for confirmation')
 Accept(p)
 if owner then owner.UpdateStateV1=realUpdate end
 H.service.UploadServerBuildSlot=upload
 C.guard(Creates()==1 and Writes()==0,'I9c: one upload, no assignment writer call',Writes())
 local row=ResultRow()
 C.guard(row~=nil and row:find('^Uploaded')~=nil and row:find('locked targets could not be saved',1,true)~=nil,
  'I9c: the row says the locked targets could not be saved',row)
 local r=Result()
 C.guard(r~=nil and r.assignNow~=true and AssignNowButton()==nil,'I9c: no Assign now for a localTargets partial')
 local hover=ResultHover() or ''
 C.expect(hover:find('from the Echo Journal',1,true)~=nil and hover:find('updates the same Wishlist',1,true)~=nil,
  'I9c: its hover names the safe next step (save the uploaded Wishlist from the Journal)',hover)
end)

C.scenario('I9d C1: a write kept only for this session says so; an owner change retires the result',function()
 Boot({active=2,slots=World()})
 NewDraft('Session plan')
 local store=Nexus.Store
 local status=store.StateWriteStatus
 local p=Click(ApplyButton())
 C.setup(p~=nil,'I9d: fixture: Create asks for confirmation')
 store.StateWriteStatus=function() return {mode='unavailable',reason='database'} end
 local said=Heard(function() Accept(p) end)
 store.StateWriteStatus=status
 C.guard(Creates()==1 and Stored(2)~=nil and Stored(2).name=='Session plan','I9d: the upload and the writer ran',Facts())
 local row=ResultRow()
 C.expect(row~=nil and row:find('for this session only',1,true)~=nil,'I9d: the row says the assignment lasts this session only',row)
 local hover=ResultHover() or ''
 C.expect(hover:find('cannot be written right now',1,true)~=nil,'I9d: its hover says saved data cannot be written',hover)
 C.expect(said:find('this session only',1,true)~=nil,'I9d: the chat says so too',said)
 C.setup(Result()~=nil,'I9d: fixture: the result is current before the owner changes')
 local key=store.CurrentOwnerKey
 store.CurrentOwnerKey=function() return 'someone-else@elsewhere' end
 local retired=Result()==nil
 store.CurrentOwnerKey=key
 C.guard(retired,'I9d: a Store owner change retires the result')
end)

C.scenario('I10 F1/C3: Unassign retires an Assigned result and Restore does not bring it back',function()
 Boot({active=2,slots=World()})
 NewDraft('Forget plan')
 local p=Click(ApplyButton())
 C.setup(p~=nil,'I10: fixture: Create asks for confirmation')
 Accept(p)
 local r=Result()
 C.setup(r~=nil and r.kind=='assigned','I10: fixture: the Create is assigned to Saved Build 2',Describe(r))
 C.setup(A.ClearLoadoutWishlist(2)==true,'I10: fixture: Saved Build 2 is unassigned (an explicit action)')
 Nexus.WishlistEditor.Refresh()
 C.guard(Result()==nil and ResultRow()==nil,'I10: the Assigned result is retired on the next refresh')
 local ok=Ctrl().RestoreForgottenPlan()
 C.setup(ok and Stored(2)~=nil and Stored(2).name=='Forget plan','I10: fixture: Restore puts the plan back on Saved Build 2',Facts())
 Nexus.WishlistEditor.Refresh()
 C.guard(Result()==nil and ResultRow()==nil,'I10: Restore does not bring the old result back')
end)

C.scenario('I10b C3: the automatic promotion retires the First-run result',function()
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 NewDraft('Starter plan',201174)
 local p=Click(ApplyButton())
 C.setup(p~=nil,'I10b: fixture: Create asks for confirmation')
 Accept(p)
 local r=Result()
 C.setup(r~=nil and r.kind=='firstRun','I10b: fixture: the Create is the first-run target',Describe(r))
 MirrorAt(108,LastCreate())
 SetRows({[2]={name='Fire PvE',verified=true,echoes=H.Clone(E2)}},2)
 A.Wishlist()
 C.setup(Stored(2)~=nil and Stored(2).name=='Starter plan' and not Stored('first'),
  'I10b: fixture: the first-run plan was promoted to Saved Build 2',Facts())
 Nexus.WishlistEditor.Refresh()
 C.guard(Result()==nil,'I10b: the promotion retires the First-run result')
end)

C.scenario('I11 PRIORITY.N4: a writer error after the upload is uploaded-then-stopped; the draft is not sent again',function()
 Boot({active=2,slots=World()})
 NewDraft('Writer error plan')
 local real=A.SetLoadoutWishlistIdentity
 A.SetLoadoutWishlistIdentity=function() error('synthetic writer failure') end
 local p=Click(ApplyButton())
 C.setup(p~=nil,'I11: fixture: Create asks for confirmation')
 local ok,err=pcall(Accept,p)
 A.SetLoadoutWishlistIdentity=real
 C.setup(not ok and Creates()==1,'I11: fixture: the upload was sent, then the writer raised',err)
 local r=Result()
 C.expect(r~=nil and r.kind=='partial' and r.reason=='error','I11: recorded as uploaded, then stopped by an error',Describe(r))
 C.expect(type(err)=='string' and err:find('synthetic writer failure',1,true)~=nil and err:find('traceback',1,true)~=nil,
  'I11: the error keeps its message and its stack',err)
 H.Advance(4)
 local again=Click(ApplyButton());if again then Accept(again) end
 C.guard(again==nil and Creates()==1,'I11: the uploaded draft is not uploaded again',Creates())
end)

C.scenario('I12 spacing: a waiting Create keeps its confirmed destination; a taken name is still refused',function()
 -- A first-run Create waits for the spacing guard; its destination changes meanwhile.
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 C.setup(KnownSlotUpload(A.UploadWishlist,103,'Spacer',H.Clone(EF))==true,'I12: fixture: an earlier upload starts the spacing window')
 NewDraft('Waiting plan',201174)
 local p=Click(ApplyButton())
 C.setup(p~=nil,'I12: fixture: Create asks for confirmation')
 Accept(p)
 C.setup(Nexus.WishlistEditor.IsApplyPending() and Creates()==0,'I12: fixture: the Create waits for the spacing guard')
 local rows=H.Clone(H.perks.serverBuildSlots);rows[1]={name='One',verified=true,echoes=H.Clone(E1)}
 H.perks.serverBuildSlots=rows;H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 H.Advance(5)
 print('OBSERVED','I12 creates='..Creates()..' facts='..Facts())
 C.expect(Creates()==0 and not Stored('first'),'I12: the waiting Create is not redirected when its destination changes',Facts())
 C.guard(not Nexus.WishlistEditor.IsApplyPending(),'I12: nothing stays queued')
 -- A name another Wishlist takes while the Create waits is refused (unchanged).
 Boot({active=2,slots=World()})
 C.setup(KnownSlotUpload(A.UploadWishlist,103,'Spacer',H.Clone(EF))==true,'I12b: fixture: an earlier upload starts the spacing window')
 NewDraft('Spaced')
 p=Click(ApplyButton())
 Accept(p)
 C.setup(Nexus.WishlistEditor.IsApplyPending(),'I12b: fixture: the Create waits for the spacing guard')
 rows=H.Clone(H.perks.serverBuildSlots);rows[120]={name='Spaced',verified=false,echoes=H.Clone(EF)}
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll()
 local said=Heard(function() H.Advance(5) end)
 C.guard(Creates()==0 and said:find('now exists',1,true)~=nil,'I12b: a name taken while the Create waited is not uploaded',said)
end)

C.scenario('I13 M2 N1 and UTF-8: chat says what the editor captured; a multibyte copy name stays whole',function()
 Boot({active=1,slots=World()})
 local opened=Nexus.WishlistEditor.OpenForCandidate({title='Copied plan',echoes=H.Clone(EF)})
 C.setup(opened,'I13: fixture: a copied draft while Saved Build One is selected')
 Nexus.WishlistEditor.Refresh()
 local p=Click(EditorButton('Create Wishlist'))
 C.setup(p~=nil,'I13: fixture: Create asks for confirmation')
 local said=Heard(function() Accept(p) end)
 C.expect(said:find('did not capture a Saved Build',1,true)~=nil and not said:find('No Saved Build was open',1,true),
  'I13: the chat says the editor captured no Saved Build (not that none was open)',said)
 -- A taken name with 3- and 4-byte UTF-8 letters: the copy name keeps them whole.
 Boot({active=2,slots=World({[108]={name='R\226\130\172n \240\159\142\178',verified=false,echoes=H.Clone(EF)}})})
 NewDraft('R\226\130\172n \240\159\142\178')
 p=Click(ApplyButton())
 local title=p and tostring(p.arg1) or ''
 local whole=title:find('^R\226\130\172n \240\159\142\178 %(Copy %d+%)$')~=nil
 C.guard(whole,'I13: the copy name keeps the multibyte letters whole and adds the copy suffix',title)
 if p then Cancel(p) end
end)

C.scenario('I14 PRIORITY.N2: a copy name offered while the server list is not loaded still says names were not checked',function()
 Boot({active=1,slots=World()})
 local ok,why=A.SetLoadoutWishlistIdentity(1,'Kept plan',H.Clone(E1))
 C.setup(ok,'I14: fixture: a retained plan named Kept plan',why)
 -- The server list stops loading: names are known only from saved plans.
 H.perks.serverBuildSlots=nil;H.Notify();A.Poll();H.Advance(1)
 NewDraft('Kept plan')
 local p=Click(ApplyButton())
 local asked=Asked(p)
 print('OBSERVED','I14 confirmation='..tostring(asked))
 C.setup(p~=nil,'I14: fixture: Create asks for confirmation')
 C.guard(p~=nil and p.arg1=='Kept plan (Copy 1)','I14: the retained name is avoided with a copy name',p and p.arg1)
 C.expect(asked~=nil and asked:find("A Wishlist named 'Kept plan' already exists",1,true)~=nil
  and asked:find('could not be checked',1,true)~=nil,
  'I14: the confirmation names the copy name and that the server list was not checked',asked)
 if p then Cancel(p) end
 C.guard(Creates()==0,'I14: nothing is uploaded by the confirmation')
end)

-- The accept button the confirmation shows (the dialog's label at show time).
local function AcceptLabel(p) return p and StaticPopupDialogs[p.which] and StaticPopupDialogs[p.which].button1 or nil end
local function Copies(rec,id)
 if type(rec)~='table' then return nil end
 local n=0;for _,e in ipairs(rec.echoes or {}) do if e.spellId==id then n=n+(e.stacks or 1) end end;return n
end

C.scenario('I15 the visible actions name what they do; each confirmation accepts with the same words',function()
 Boot({active=2,slots=World()})
 NewDraft('Labelled plan')
 local apply,only=ApplyButton(),EditorButton('Create unassigned')
 print('OBSERVED','I15 new plan with destination labels='..EditorLabels())
 C.expect(Label(apply)=='Create & assign' and only~=nil and only~=apply,
  'I15: a new plan with a captured destination shows Create & assign with Create unassigned beside it',EditorLabels())
 local w=Writes()
 local p=Click(apply)
 C.expect(p~=nil and p.which=='WISHLISTREALIZER_CREATE_WISHLIST' and AcceptLabel(p)=='Create & assign',
  'I15: its confirmation accepts with Create & assign',AcceptLabel(p))
 Cancel(p)
 p=Click(only)
 C.expect(p~=nil and AcceptLabel(p)=='Create unassigned','I15: Create unassigned\'s confirmation accepts with Create unassigned',AcceptLabel(p))
 Cancel(p)
 C.guard(Creates()==0 and Writes()==w,'I15: opening and cancelling either confirmation uploads and assigns nothing')
 -- No captured destination: the one action is Create unassigned.
 Boot({active=1,slots=World()})
 local opened=Nexus.WishlistEditor.OpenForCandidate({title='Copied plan',echoes=H.Clone(EF)})
 C.setup(opened and Ctrl().CreateTargetContext()==nil,'I15: fixture: a copied draft with no captured destination')
 Nexus.WishlistEditor.Refresh()
 local n=0
 for _,f in ipairs(H.frames) do
  if f.kind=='Button' and f:IsVisible() and f:GetParent()==NexusEditorFrame and Label(f)=='Create unassigned' then n=n+1 end
 end
 C.expect(Label(ApplyButton())=='Create unassigned' and n==1 and EditorButton('Create & assign')==nil,
  'I15: a draft without a destination shows only Create unassigned',EditorLabels())
 p=Click(ApplyButton())
 C.expect(p~=nil and AcceptLabel(p)=='Create unassigned' and p.data and p.data.intent=='saveChanges',
  'I15: and its confirmation is the Save changes intent, accepted with Create unassigned',AcceptLabel(p))
 Cancel(p)
 -- An opened Wishlist that its Saved Build holds: Save changes only.
 Boot({active=6,slots=World()})
 local ok=A.SetLoadoutWishlistIdentity(6,'W-Six',H.Clone(E6))
 C.setup(ok,'I15: fixture: Saved Build 6 is assigned W-Six')
 H.Notify();A.Poll();H.Advance(1)
 SlashCmdList.NEXUS('editor')
 local ctx=Ctrl().EditingContext() or {}
 C.setup(ctx.name=='W-Six' and ctx.loadoutSlot==6,'I15: fixture: the editor opens W-Six for Saved Build 6',ctx.name)
 Nexus.WishlistEditor.Refresh()
 C.expect(Label(ApplyButton())=='Save changes' and EditorButton('Save & assign')==nil,
  'I15: an opened Wishlist that its Saved Build holds shows Save changes only',EditorLabels())
 local labels=EditorLabels()
 C.expect(not labels:find('Create Wishlist',1,true) and not labels:find('Save Wishlist',1,true),
  'I15: no ambiguous Create Wishlist / Save Wishlist action is shown in the editor',labels)
end)

C.scenario('I16 explicit Save changes writes no destination the plan did not have; Save & assign is the assigning action',function()
 -- (a) W-Free opened for Saved Build 6, which holds W-Six.
 Boot({active=6,slots=World()})
 local ok=A.SetLoadoutWishlistIdentity(6,'W-Six',H.Clone(E6));writes.SetLoadoutWishlistIdentity=0
 C.setup(ok,'I16: fixture: Saved Build 6 is assigned W-Six')
 H.Notify();A.Poll();H.Advance(1)
 for _,cand in ipairs(A.GetWishlistCandidates()) do if cand.slot==107 then Nexus.WishlistEditor.OpenForWishlist(cand,6) end end
 local ctx=Ctrl().EditingContext() or {}
 C.setup(ctx.name=='W-Free' and ctx.loadoutSlot==6,'I16: fixture: W-Free is open for Saved Build 6',ctx.name)
 selected(201174).plus:Click()
 Nexus.WishlistEditor.Refresh()
 local apply,changes=ApplyButton(),EditorButton('Save changes')
 print('OBSERVED','I16 opened-for labels='..EditorLabels())
 C.expect(Label(apply)=='Save & assign' and changes~=nil and changes~=apply,
  'I16: a Wishlist opened for a Saved Build that holds another plan shows Save & assign with Save changes beside it',EditorLabels())
 local facts,w,others=Facts(),Writes(),Others()
 local p=Click(changes)
 local asked=Asked(p)
 print('OBSERVED','I16 Save changes confirmation='..tostring(asked))
 C.expect(p~=nil and p.which=='WISHLISTREALIZER_UPDATE_WISHLIST' and AcceptLabel(p)=='Save changes'
  and p.data and p.data.keepsAssignment==true and asked and asked:find('keeps the Wishlist it uses now',1,true)~=nil
  and not asked:find('Saving also updates its assignment',1,true),
  'I16: Save changes asks to save without assigning, and says the Saved Build keeps its Wishlist',asked)
 Accept(p)
 C.expect(Uploads(107)==1 and Writes()==w and Facts()==facts and Stored(6)~=nil and Stored(6).name=='W-Six',
  'I16: Save changes uploads W-Free once and changes no assignment (Saved Build 6 keeps W-Six)',Facts())
 local r=Result()
 C.expect(r~=nil and r.kind=='unassigned' and r.reason=='saveOnly' and r.intent=='saveChanges',
  'I16: its result says saved without an assignment, as chosen',Describe(r))
 C.guard(Others()==others and spends==0,'I16: no other game action and no spend')
 -- (b) Save & assign of the same editor assigns it to the Saved Build it was opened for.
 H.Advance(4)
 selected(201174).plus:Click()
 Nexus.WishlistEditor.Refresh()
 local sent=Uploads(107)
 p=Click(ApplyButton())
 C.expect(p~=nil and AcceptLabel(p)=='Save & assign' and p.data and p.data.intent=='saveAndAssign',
  'I16: Save & assign\'s confirmation is the assigning intent, accepted with Save & assign',AcceptLabel(p))
 Accept(p)
 C.guard(Uploads(107)==sent+1 and writes.UpdateWishlistAssociationAfterSave==1 and Stored(6)~=nil and Stored(6).name=='W-Free',
  'I16: the assigning save makes W-Free Saved Build 6\'s Wishlist through the existing writer',Facts())
 r=Result()
 C.expect(r~=nil and r.kind=='assigned' and r.intent=='saveAndAssign','I16: its result names Save & assign',Describe(r))
 local rows=H.Clone(H.perks.serverBuildSlots);rows[107]={name='W-Free',verified=false,echoes=H.Clone(H.actions[#H.actions][4])}
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll();H.Advance(1);Nexus.WishlistEditor.Refresh()
 C.expect(Label(ApplyButton())=='Save changes' and EditorButton('Save & assign')==nil,
  'I16: once Saved Build 6 holds it, the editor offers Save changes only',EditorLabels())
 -- (c) The opened first-run plan, chosen in the picker, has no slot-1 handoff.
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 C.setup(A.SetFirstRunWishlist(107)==true and Stored('first')~=nil and Stored(1)==nil,
  'I16c: fixture: W-Free is the first-run plan and Saved Build slot 1 holds no assignment',Facts())
 writes.SetFirstRunWishlist=0
 SlashCmdList.NEXUS('editor')
 ctx=Ctrl().EditingContext() or {}
 C.setup(ctx.name=='W-Free' and ctx.destination=='first','I16c: fixture: the editor opens the first-run plan',ctx.name)
 selected(201174).plus:Click()
 Nexus.WishlistEditor.Refresh()
 C.setup(Label(ApplyButton())=='Save changes' or Label(ApplyButton())=='Save Wishlist','I16c: fixture: the save control',EditorLabels())
 p=Click(ApplyButton())
 C.setup(p~=nil,'I16c: fixture: Save asks for confirmation')
 Accept(p)
 print('OBSERVED','I16c facts='..Facts())
 C.guard(Uploads(107)==1 and Stored('first')~=nil and Copies(Stored('first'),201174)==2,
  'I16c: Save changes uploads once and updates the first-run plan',Facts())
 C.expect(Stored(1)==nil,'I16c: an explicit Save changes creates no new slot-1 handoff (no new destination)',Facts())
 -- Legacy direct controller call (no intent named): the writers' earlier rule, kept separately.
 Boot({active=0,slots={[107]={name='W-Free',verified=false,echoes=EF}}})
 C.setup(A.SetFirstRunWishlist(107)==true and Stored(1)==nil,'I16c legacy: fixture: the same first-run plan')
 SlashCmdList.NEXUS('editor')
 selected(201174).plus:Click()
 local c=Ctrl()
 local data=c.PrepareApply(nil)
 C.setup(data~=nil,'I16c legacy: fixture: the default-intent confirmation is prepared')
 local accepted=data and c.AcceptApply(data)
 C.guard(accepted==true and Uploads(107)==1 and Stored(1)~=nil and Stored('first')~=nil
  and Stored(1).assignmentId==Stored('first').assignmentId,
  'I16c legacy: a caller that names no intent keeps the earlier handoff rule',Facts())
end)

C.scenario('I17 PRIORITY.N4: a designed target that becomes locked after Create; pressing Create again sends nothing',function()
 Boot({active=2,slots=World()})
 H.locked={};H.Notify();A.Poll();H.Advance(1)
 local W=Nexus.WishlistEditor
 local plan={{spellId=201175,quality=0,stacks=1,locked=false},{spellId=201176,quality=0,stacks=1,locked=true}}
 local code=Nexus.Codec and Nexus.Codec.EncodeEBH1 and Nexus.Codec.EncodeEBH1(plan,'MAGE','Locked plan')
 C.setup(code~=nil,'I17: fixture: a plan code with one ordinary row and one locked target')
 if not code then return end
 W.ImportEBH1String(code,'Locked plan')
 local c=Ctrl()
 C.setup(W.DebugDraftState().pendingLock==1 and (c.FulfilledDraftTargets() or {})[201176]==nil,
  'I17: fixture: the draft designs locked target 201176, not owned yet')
 local p=Click(ApplyButton())
 C.setup(p~=nil,'I17: fixture: Create asks for confirmation')
 Accept(p)
 C.setup(Creates()==1 and Stored(2)~=nil and Stored(2).name=='Locked plan','I17: fixture: the Create uploaded once and is assigned',Facts())
 -- The production path: the game's locked list (GetLockedPerks) now holds the
 -- target; the adapter's trusted projection reaches the editor's refresh,
 -- which reconciles the draft passively (Controller.ReconcileLocked).
 H.locked={{spellId=201176,stacks=1}};H.Notify();A.Poll();H.Advance(1);W.Refresh()
 C.setup(W.DebugDraftState().pendingLock==0 and (c.FulfilledDraftTargets() or {})[201176]~=nil,
  'I17: fixture: the refresh reconciled the target into a fulfilled one (no edit by the player)')
 H.Advance(4)
 local again
 local said=Heard(function() again=Click(ApplyButton());if again then Accept(again) end end)
 print('OBSERVED','I17 creates='..Creates()..' offered='..tostring(again~=nil)..' said='..said)
 C.guard(again==nil and Creates()==1 and writes.SetLoadoutWishlistIdentity==1 and not said:find('will be named',1,true),
  'I17: after the passive reconciliation, pressing Create again sends nothing and offers no copy name',said)
end)

C.finish('(Save changes vs Save & assign intents; bound destinations; truthful partial/unconfirmed results; no repeat upload)')
