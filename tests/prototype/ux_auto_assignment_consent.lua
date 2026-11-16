-- M3 (UX-03 Save & assign consent): Save & assign of a new plan names the
-- destination this editor captured and, through its deliberate confirmation,
-- discloses Auto's existing consequence for that Saved Build: none with Auto
-- OFF; the conditional replacement with Auto ON; with Auto selected but held,
-- why it was not acting at its last update; with its finished-run save
-- permission off, that Auto does not replace the Saved Build. Cancel, a
-- stale context or Save changes write no destination; accept writes exactly
-- the named one. Nothing here changes Auto, a permission, a default or sends.
-- Categories (view_regression_support): EXPECT is behaviour added in M3 (it
-- fails on the accepted predecessor ea3268a8); GUARD already holds there and
-- must keep holding; SETUP is the fixture. Oracles: the host upload call, the
-- counted assignment writers, the Store, Auto's state and the confirmation
-- the client shows. Real TOC boot, runtime, editor and its StaticPopup
-- handlers; synthetic host services only. No native StaticPopup claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_auto_assignment_consent')
local H,A,writes,spends
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local E3={{spellId=201176,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}
-- Words that would promise an unconditional or immediate replacement.
local BANNED={'within seconds','right away','immediately','will replace','at once'}

local function World()
 return {[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [3]={name='Arena',verified=true,echoes=E3},[107]={name='W-Free',verified=false,echoes=EF}}
end
local function Boot()
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;EchoJournalMicroButton=nil
 NexusEditorFrame=nil;NexusWishlistNameInput=nil;NexusWishlistEditorSwitchButton=nil
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusWishlistAssignNowButton=nil
 NexusWishlistEditorLoadoutMenu=nil;NexusWishlistSaveOnlyButton=nil;NexusPanel=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201174,'Echo Free',0,5)
 H.AddEcho(201175,'Echo Fire',0,5);H.AddEcho(201176,'Echo Arena',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots=World()
 H.perks.serverActiveSlot=2
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
local function ClickCatalog(id)
 for _,f in ipairs(H.frames)do if f.kind=='Button' and f:IsVisible() and f.status and f.data and f.data.spellId==id then f:Click();return true end end
 error('visible catalog row absent: '..id)
end
local function Click(button)
 if not button then return nil end
 local before=H.popup
 button:Click()
 if H.popup~=nil and H.popup~=before then return H.popup end
 return nil
end
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
local function Asked(p)
 if not p then return nil end
 local d=StaticPopupDialogs[p.which] or {}
 local ok,s=pcall(string.format,tostring(d.text or ''),p.arg1,p.arg2)
 return V.Plain(ok and s or tostring(d.text or ''))
end
local function Creates() local n=0;for _,a in ipairs(H.actions) do if a[1]=='upload' and a[2]==0 then n=n+1 end end;return n end
local function Others() local n=0;for _,a in ipairs(H.actions) do if a[1]~='upload' then n=n+1 end end;return n end
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Stored(slot) local s=Nexus.Store.State();return s.loadoutWishlists and s.loadoutWishlists[slot] end
local function Facts()
 local s=Nexus.Store.State() or {};local links=type(s.loadoutWishlists)=='table' and s.loadoutWishlists or {}
 local out={}
 for slot=1,6 do local r=links[slot]
  out[#out+1]=slot..'='..(type(r)=='table' and (tostring(r.name)..'/'..tostring(r.assignmentId)) or tostring(r)) end
 local f=s.firstRunWishlist
 out[#out+1]='first='..(type(f)=='table' and (tostring(f.name)..'/'..tostring(f.assignmentId)) or tostring(f))
 return table.concat(out,' ')
end
-- Every saved setting, as one comparable string (permissions included).
local function Settings()
 local s=Nexus.Store.Settings() or {}
 local keys={}
 for k,v in pairs(s) do if type(v)~='table' and type(v)~='function' then keys[#keys+1]=tostring(k)..'='..tostring(v) end end
 table.sort(keys)
 return table.concat(keys,';')
end
local function Conditional(text)
 local l=tostring(text or ''):lower()
 for _,w in ipairs(BANNED) do if l:find(w,1,true) then return false,w end end
 return true
end
local function TurnAutoOn()
 SlashCmdList.NEXUS('auto');H.Advance(.2,.1)
end
-- A new draft for the active Saved Build (Fire PvE, slot 2).
local function NewDraft(name)
 SlashCmdList.NEXUS('editor')
 NexusWishlistNameInput:SetText(name);ClickCatalog(201175)
 Nexus.WishlistEditor.Refresh()
end
local function Apply()
 local b=EditorButton('Create Wishlist')
 return Click(b)
end

C.scenario('A1 Auto OFF: the destination is named, no Auto line; cancel changes nothing; accept writes exactly it',function()
 Boot()
 C.setup(not Auto(),'A1: fixture: Auto is OFF')
 NewDraft('Consent off')
 local facts,others,settings=Facts(),Others(),Settings()
 local p=Apply()
 local asked=Asked(p)
 print('OBSERVED','A1 confirmation='..tostring(asked))
 C.setup(p~=nil,'A1: fixture: Create Wishlist asks for confirmation')
 C.guard(asked~=nil and V.Names(asked,'Fire PvE') and asked:find('slot 2',1,true)~=nil and not asked:find('Auto is ON',1,true),
  'A1: with Auto OFF the captured Saved Build is named and no Auto line is added',asked)
 C.expect(p~=nil and type(p.data)=='table' and type(p.data.confirmation)=='table'
  and p.data.confirmation.intent=='saveAndAssign' and p.data.confirmation.destinationKey=='savedBuild:2',
  'A1: the confirmation binds Save & assign to Saved Build 2')
 Cancel(p)
 C.guard(Creates()==0 and Writes()==0 and Facts()==facts and Settings()==settings,'A1: Cancel uploads, assigns and changes nothing')
 p=Apply()
 Accept(p)
 C.guard(Creates()==1 and writes.SetLoadoutWishlistIdentity==1 and Writes()==1 and Stored(2)~=nil
  and Stored(2).name=='Consent off' and Stored(3)==nil,'A1: accept assigns exactly the named Saved Build',Facts())
 C.guard(Others()==others and spends==0 and not Auto() and Settings()==settings,'A1: no other action, spend, Auto or setting change')
end)

C.scenario('A2 Auto ON: the conditional replacement is disclosed; cancel and accept change no Auto state',function()
 Boot()
 TurnAutoOn()
 C.setup(Auto(),'A2: fixture: Auto is ON')
 NewDraft('Consent on')
 local settings=Settings()
 local p=Apply()
 local asked=Asked(p)
 print('OBSERVED','A2 confirmation='..tostring(asked))
 local ok,word=Conditional(asked)
 C.guard(asked~=nil and asked:find('Auto is ON',1,true)~=nil and asked:find('may replace',1,true)~=nil
  and asked:find('level 80',1,true)~=nil and V.Names(asked,'Fire PvE') and ok,
  'A2: the Auto line names the conditional replacement of Fire PvE and promises no immediate one',word or asked)
 Cancel(p)
 C.guard(Creates()==0 and Writes()==0 and Auto(),'A2: Cancel changes nothing; Auto stays ON')
 p=Apply()
 Accept(p)
 C.guard(Creates()==1 and Stored(2)~=nil and Stored(2).name=='Consent on' and Auto() and Settings()==settings,
  'A2: accept assigns the named Saved Build; Auto and every setting are unchanged',Facts())
 C.guard(spends==0,'A2: nothing is spent')
end)

C.scenario('A3 Auto ON but held: the confirmation says why Auto was not acting',function()
 Boot()
 Nexus.Panel.Show()
 TurnAutoOn()
 C.setup(Auto(),'A3: fixture: Auto is ON')
 -- The game's own auto-accept is turned on: Auto stays selected but holds.
 ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',true)
 Nexus.RequestRecompute();H.Advance(1)
 local model=Nexus.Panel._lastModel
 local held=type(model)=='table' and model.auto==true and type(model.paused)=='string' and model.paused or nil
 C.setup(Auto() and held~=nil,'A3: fixture: Auto is ON and held at its last update',held)
 NewDraft('Consent held')
 local p=Apply()
 local asked=Asked(p)
 print('OBSERVED','A3 confirmation='..tostring(asked))
 local ok,word=Conditional(asked)
 C.guard(asked~=nil and asked:find('Auto is ON',1,true)~=nil and asked:find('may replace',1,true)~=nil and ok,
  'A3: the conditional Auto line is still shown for the held Auto',word or asked)
 -- The plain words for the hold the HUD recorded (the game's auto-accept here).
 local R=Nexus.Readout
 local plain=R and R.AutoHoldText and held and R.AutoHoldText(held) or nil
 C.expect(asked~=nil and asked:find('paused at its last update',1,true)~=nil
  and plain~=nil and asked:find(plain,1,true)~=nil,
  'A3: it says, in plain words, why the held Auto was not acting',asked)
 Cancel(p)
 C.guard(Creates()==0 and Writes()==0 and Auto(),'A3: Cancel changes nothing; Auto stays selected')
 ProjectEbonholdOptionsService:SetSetting('autoAcceptLoadoutEchoes',false)
end)

C.scenario('A4 Auto ON with its finished-run save permission off: no replacement is promised',function()
 Boot()
 TurnAutoOn()
 local settings=Nexus.Store.Settings()
 settings.autoSave=false
 C.setup(Auto() and Nexus.Store.Settings().autoSave==false,'A4: fixture: Auto is ON and autoSave is off')
 NewDraft('Consent nosave')
 local p=Apply()
 local asked=Asked(p)
 print('OBSERVED','A4 confirmation='..tostring(asked))
 C.expect(asked~=nil and asked:find('permission to save finished runs (autoSave) is off',1,true)~=nil
  and not asked:find('may replace',1,true),'A4: with autoSave off the confirmation says Auto does not replace the Saved Build',asked)
 Cancel(p)
 C.guard(Creates()==0 and Nexus.Store.Settings().autoSave==false and Auto(),'A4: reading it changes no setting and no Auto state')
 settings.autoSave=true
end)

C.scenario('A5 Save changes (Create unassigned) writes no destination and carries no Auto line',function()
 Boot()
 TurnAutoOn()
 C.setup(Auto(),'A5: fixture: Auto is ON')
 NewDraft('Consent none')
 local facts=Facts()
 local only=EditorButton('Create unassigned')
 local p=Click(only)
 local asked=Asked(p)
 print('OBSERVED','A5 confirmation='..tostring(asked))
 C.expect(asked~=nil and asked:find('saved without an assignment',1,true)~=nil and not asked:find('Auto is ON',1,true),
  'A5: Save changes names no assignment and no Auto consequence',asked)
 Accept(p)
 C.expect(Creates()==1 and Writes()==0 and Facts()==facts,'A5: it uploads once and writes no destination',Facts())
 C.guard(Auto() and spends==0,'A5: Auto stays ON; nothing is spent')
end)

C.scenario('A6 stale context: a Saved Build assigned elsewhere meanwhile is kept; nothing is uploaded',function()
 Boot()
 NewDraft('Consent stale')
 local p=Apply()
 C.setup(p~=nil,'A6: fixture: Create Wishlist asks for confirmation')
 -- An explicit Assign of Saved Build 2 elsewhere, before the accept.
 local ok=A.SetLoadoutWishlistIdentity(2,'Other plan',H.Clone(E3))
 C.setup(ok,'A6: fixture: Saved Build 2 is assigned Other plan elsewhere')
 local w=Writes()
 Accept(p)
 C.guard(Creates()==0 and Writes()==w and Stored(2)~=nil and Stored(2).name=='Other plan',
  'A6: the newer choice is kept and nothing is uploaded or written',Facts())
end)

-- UX-05: the Echo Journal's Wishlist chooser (the picker). Its rows assign
-- the Wishlist to the Saved Build the picker was opened for.
local CONSENT='NEXUS_ASSIGN_WISHLIST_AUTO_ON'
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
-- The client hides a dialog on Cancel; this one has nothing to undo.
local function Dismiss(p)
 if not p then return end
 local d=StaticPopupDialogs[p.which]
 if H.popup==p then H.popup=nil end
 if d and type(d.OnCancel)=='function' then d.OnCancel(p.frame,p.data) end
end

C.scenario('A7 UX-05 Auto OFF: one picker click assigns and says so; no confirmation',function()
 Boot()
 C.setup(not Auto(),'A7: fixture: Auto is OFF')
 C.setup(OpenPicker(),'A7: fixture: the Wishlist chooser is open for Saved Build 2 (Fire PvE)')
 local row=PickerRow('W-Free')
 C.setup(row~=nil,'A7: fixture: the chooser lists W-Free')
 if not row then return end
 local settings,others=Settings(),Others()
 H.popup=nil
 local said=Heard(function() row.nameButton:Click() end)
 print('OBSERVED','A7 said='..said)
 C.guard(H.popup==nil and writes.SetLoadoutWishlist==1 and Stored(2)~=nil and Stored(2).name=='W-Free',
  'A7: with Auto OFF the click assigns W-Free to Saved Build 2 at once, through the existing writer',Facts())
 C.expect(said:find("'W-Free' is now the Wishlist for Saved Build 'Fire PvE'",1,true)~=nil
  and said:find('No Saved Build was changed or activated',1,true)~=nil,
  'A7: a visible line confirms what changed, and only that',said)
 C.guard(Creates()==0 and Others()==others and spends==0 and not Auto() and Settings()==settings,
  'A7: no upload, game action, spend, Auto or setting change')
end)

C.scenario('A8 UX-05 Auto ON: the picker asks first; Cancel changes nothing',function()
 Boot()
 TurnAutoOn()
 C.setup(Auto(),'A8: fixture: Auto is ON')
 C.setup(OpenPicker(),'A8: fixture: the Wishlist chooser is open for Saved Build 2 (Fire PvE)')
 local row=PickerRow('W-Free')
 C.setup(row~=nil,'A8: fixture: the chooser lists W-Free')
 if not row then return end
 local facts,settings,others=Facts(),Settings(),Others()
 H.popup=nil
 row.nameButton:Click()
 local p=H.popup
 local asked=Asked(p)
 print('OBSERVED','A8 confirmation='..tostring(asked))
 C.expect(p~=nil and p.which==CONSENT and Writes()==0 and Facts()==facts,
  'A8: with Auto ON the click asks before assigning; nothing is assigned yet',Facts())
 C.expect(asked~=nil and V.Names(asked,'W-Free') and V.Names(asked,'Fire PvE') and asked:find('Auto is ON',1,true)~=nil
  and asked:find('may replace',1,true)~=nil and asked:find('level 80',1,true)~=nil
  and asked:find('Cancel changes nothing',1,true)~=nil and asked:find('turn Auto OFF, then assign',1,true)~=nil,
  'A8: it names the Wishlist, the Saved Build, the conditional replacement and the safe alternative',asked)
 C.expect(p~=nil and StaticPopupDialogs[p.which].button1=='Assign' and StaticPopupDialogs[p.which].button2=='Cancel',
  'A8: its buttons are Assign and Cancel')
 -- Measured after the click: Cancel itself changes nothing.
 local asking,written=Facts(),Writes()
 Dismiss(p)
 C.guard(Writes()==written and Facts()==asking and Auto() and Settings()==settings and Others()==others and spends==0,
  'A8: Cancel assigns nothing and changes no Auto state or setting',Facts())
end)

C.scenario('A9 UX-05 Auto ON: Assign assigns the captured Saved Build; Auto is not changed',function()
 Boot()
 TurnAutoOn()
 C.setup(Auto() and OpenPicker(),'A9: fixture: Auto is ON and the chooser is open for Saved Build 2')
 local row=PickerRow('W-Free')
 C.setup(row~=nil,'A9: fixture: the chooser lists W-Free')
 if not row then return end
 local settings=Settings()
 H.popup=nil
 row.nameButton:Click()
 local p=H.popup
 C.expect(p~=nil and p.which==CONSENT,'A9: the click asks first')
 if not p then return end
 -- The game now shows Saved Build 3 as active: the accept still assigns the
 -- Saved Build the chooser was opened for and the confirmation named.
 H.perks.serverActiveSlot=3;H.Notify();A.Poll();H.Advance(1)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','A9 said='..said)
 C.expect(writes.SetLoadoutWishlist==1 and Stored(2)~=nil and Stored(2).name=='W-Free' and Stored(3)==nil,
  'A9: Assign writes exactly the named Saved Build 2 (not the one active now)',Facts())
 C.expect(said:find("'W-Free' is now the Wishlist for Saved Build 'Fire PvE'",1,true)~=nil,'A9: and says so',said)
 C.guard(Auto() and Settings()==settings and Creates()==0 and spends==0,'A9: Auto stays ON; no setting, upload or spend')
end)

C.scenario('A10 UX-05 a confirmation answered after the character data changed assigns nothing',function()
 Boot()
 TurnAutoOn()
 C.setup(Auto() and OpenPicker(),'A10: fixture: Auto is ON and the chooser is open')
 local row=PickerRow('W-Free')
 C.setup(row~=nil,'A10: fixture: the chooser lists W-Free')
 if not row then return end
 H.popup=nil
 row.nameButton:Click()
 local p=H.popup
 C.expect(p~=nil and p.which==CONSENT,'A10: the click asks first')
 if not p then return end
 local facts=Facts()
 local store=Nexus.Store
 local key=store.CurrentOwnerKey
 store.CurrentOwnerKey=function() return 'someone-else@elsewhere' end
 local said=Heard(function() Accept(p) end)
 store.CurrentOwnerKey=key
 C.expect(Writes()==0 and Facts()==facts and said:find('Nothing was assigned',1,true)~=nil,
  'A10: the stale answer assigns nothing and says why',said)
 C.guard(Auto(),'A10: Auto stays ON')
end)

C.scenario('A11 UX-05 no confirmation where nothing can be replaced: first-run target; an empty Saved Build is refused as before',function()
 Boot()
 TurnAutoOn()
 -- No Saved Build active: the chooser sets the first-run target.
 H.perks.serverActiveSlot=0;H.Notify();A.Poll();H.Advance(1)
 C.setup(Auto() and OpenPicker(),'A11: fixture: Auto is ON and the chooser is open for the first-run target')
 local row=PickerRow('W-Free')
 C.setup(row~=nil,'A11: fixture: the chooser lists W-Free')
 if row then
  H.popup=nil
  row.nameButton:Click()
  C.guard(H.popup==nil and writes.SetFirstRunWishlist==1 and Nexus.Store.State().firstRunWishlist~=nil,
   'A11: the first-run target is set at once (no Saved Build to replace)',Facts())
 end
 -- An empty numbered Saved Build: the assignment itself refuses, unchanged.
 Boot()
 TurnAutoOn()
 local rows=H.Clone(H.perks.serverBuildSlots);rows[3]={name='Arena',verified=true,echoes={}}
 H.perks.serverBuildSlots=rows;H.perks.serverActiveSlot=3;H.Notify();A.Poll();H.Advance(1)
 C.setup(Auto() and OpenPicker(),'A11: fixture: the chooser is open for the empty Saved Build 3')
 row=PickerRow('W-Free')
 if row then
  local facts=Facts()
  H.popup=nil
  local said=Heard(function() row.nameButton:Click() end)
  C.guard(H.popup==nil and Facts()==facts and said:find('empty or unavailable',1,true)~=nil,
   'A11: an empty Saved Build is refused with the existing reason, without a confirmation',said)
 end
 C.guard(Auto() and Creates()==0 and spends==0,'A11: Auto stays ON; nothing uploaded or spent')
end)

-- D7: a waiting Auto-ON question is bound to the Saved Build it represents
-- (its slot, name and contents when the chooser showed it), not to the slot
-- number or the name alone. Answered after that slot was saved over, renamed,
-- emptied, removed or became unreadable, it assigns nothing and asks the
-- player to choose again; a fresh question then names what the slot holds.
-- The active Saved Build is not part of it (A9), and the character check
-- stays first (A10). EXPECT here fails on the D7 preimage (18f1944e) by
-- design: there the accept wrote the captured slot number whatever it held.
-- Oracles: the counted writers, the Store, the chat line, the chooser frame
-- and the confirmation shown. Synthetic host services; no native claim.
local CHANGED='That Saved Build changed or could not be read'
local REPLACED={{spellId=201172,quality=0,stacks=1},{spellId=201174,quality=0,stacks=1}}
-- The game now reports other Saved Build rows (fresh tables, as a re-send).
local function ServerNow(change)
 local rows=H.Clone(H.perks.serverBuildSlots)
 change(rows)
 H.perks.serverBuildSlots=rows;H.Notify();A.Poll();H.Advance(1)
end
-- W-Free clicked in the chooser for Saved Build 2 with Auto ON: the waiting
-- question, or nil when none was asked.
local function AskWFree(tag)
 C.setup(Auto() and OpenPicker(),tag..': fixture: Auto is ON and the chooser is open for Saved Build 2')
 local row=PickerRow('W-Free')
 C.setup(row~=nil,tag..': fixture: the chooser lists W-Free')
 if not row then return nil end
 H.popup=nil
 row.nameButton:Click()
 local p=H.popup
 return (p~=nil and p.which==CONSENT) and p or nil
end
local function Refused(said)
 return said:find(CHANGED,1,true)~=nil and said:find('Nothing was assigned',1,true)~=nil
  and said:find('choose again',1,true)~=nil
end

C.scenario('A12 D7 the Saved Build in the named slot was replaced while the question waited: nothing is assigned; a fresh question assigns',function()
 Boot()
 TurnAutoOn()
 local p=AskWFree('A12')
 C.setup(p~=nil and V.Names(Asked(p) or '','Fire PvE'),'A12: fixture: the question names Saved Build Fire PvE')
 if not p then return end
 local facts,settings=Facts(),Settings()
 -- Another build is saved over slot 2 before the answer.
 ServerNow(function(rows) rows[2]={name='Frost PvP',verified=true,echoes=H.Clone(REPLACED)} end)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','A12 said='..said..' facts='..Facts())
 C.expect(Writes()==0 and Facts()==facts and Stored(2)==nil,
  'A12: the answer for the replaced Saved Build calls no assignment writer and stores nothing',Facts())
 C.expect(Refused(said),'A12: it says the Saved Build changed, that nothing was assigned and to choose again',said)
 C.expect(not NexusWishlistOnlyPicker:IsShown(),'A12: the chooser that still named the old Saved Build is closed')
 C.guard(Auto() and Settings()==settings and Creates()==0 and spends==0,'A12: Auto stays ON; no setting, upload or spend')
 -- The fresh question names what slot 2 holds now, and its answer assigns it.
 local again=AskWFree('A12b')
 local asked=Asked(again)
 print('OBSERVED','A12b confirmation='..tostring(asked))
 C.expect(again~=nil and again~=p and asked~=nil and V.Names(asked,'W-Free') and V.Names(asked,'Frost PvP'),
  'A12b: choosing again asks a new question naming the Saved Build the slot holds now',asked)
 if not again then return end
 said=Heard(function() Accept(again) end)
 C.expect(writes.SetLoadoutWishlist==1 and Writes()==1 and Stored(2)~=nil and Stored(2).name=='W-Free' and Stored(3)==nil,
  'A12b: the fresh answer assigns W-Free to Saved Build 2, once',Facts())
 C.expect(said:find("'W-Free' is now the Wishlist for Saved Build 'Frost PvP'",1,true)~=nil,'A12b: and says so with both names',said)
end)

C.scenario('A13 D7 the same slot and the same name with other contents is not the Saved Build that was asked about',function()
 Boot()
 TurnAutoOn()
 local p=AskWFree('A13')
 C.setup(p~=nil,'A13: fixture: the click asks first')
 if not p then return end
 local facts=Facts()
 -- Saved over under the same name: one Echo gained a stack, one was added.
 ServerNow(function(rows) rows[2]={name='Fire PvE',verified=true,
  echoes={{spellId=201175,quality=0,stacks=2},{spellId=201172,quality=0,stacks=1}}} end)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','A13 said='..said..' facts='..Facts())
 C.expect(Writes()==0 and Facts()==facts and Stored(2)==nil,
  'A13: an equal name does not stand in for the Saved Build: nothing is written',Facts())
 C.expect(Refused(said),'A13: the player is told to choose again',said)
 C.guard(Auto(),'A13: Auto stays ON')
end)

C.scenario('A14 D7 the named Saved Build was renamed while the question waited: the name asked about is no longer its name',function()
 Boot()
 TurnAutoOn()
 local p=AskWFree('A14')
 C.setup(p~=nil,'A14: fixture: the click asks first')
 if not p then return end
 local facts=Facts()
 ServerNow(function(rows) rows[2].name='Fire Raid' end)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','A14 said='..said..' facts='..Facts())
 C.expect(Writes()==0 and Facts()==facts and Stored(2)==nil and Refused(said),
  'A14: nothing is assigned under the old name; the player is told to choose again',said)
end)

C.scenario('A15 D7 a named Saved Build that is gone, empty or unreadable at the answer cannot be proved: nothing is assigned',function()
 Boot()
 TurnAutoOn()
 local world=H.Clone(H.perks.serverBuildSlots)
 local function Restore() H.perks.serverBuildSlots=H.Clone(world);H.Notify();A.Poll();H.Advance(1) end
 local cases={
  {'gone',function() ServerNow(function(rows) rows[2]=nil end) end},
  {'empty',function() ServerNow(function(rows) rows[2]={name='Fire PvE',verified=true,echoes={}} end) end},
  -- No Saved Build data at all at the moment of the answer.
  {'unreadable',function() H.perks.serverBuildSlots=nil end},
 }
 for _,case in ipairs(cases) do
  local tag='A15 '..case[1]
  local p=AskWFree(tag)
  C.setup(p~=nil,tag..': fixture: the click asks first')
  if not p then return end
  local facts,before=Facts(),Writes()
  case[2]()
  local said=Heard(function() Accept(p) end)
  print('OBSERVED',tag..' said='..said..' facts='..Facts())
  C.guard(Facts()==facts and Stored(2)==nil,tag..': nothing is stored',Facts())
  C.expect(Writes()==before and Refused(said),
   tag..': no assignment writer is called and the player is told to choose again',said)
  Restore()
 end
 C.guard(Auto() and Creates()==0 and spends==0,'A15: Auto stays ON; nothing uploaded or spent')
end)

C.scenario('A16 D7 control: the same Saved Build re-sent, other slots changed and another one active still assigns the named one',function()
 Boot()
 TurnAutoOn()
 -- Saved Build 2 holds two Echoes, so their order can differ between reads.
 ServerNow(function(rows) rows[2]={name='Fire PvE',verified=true,
  echoes={{spellId=201175,quality=0,stacks=1},{spellId=201172,quality=0,stacks=2}}} end)
 local p=AskWFree('A16')
 C.setup(p~=nil,'A16: fixture: the click asks first')
 if not p then return end
 local settings=Settings()
 -- The same Saved Build 2 arrives again in fresh tables with its Echoes in
 -- the other order; Saved Build 1 is renamed, Saved Build 3 is saved over
 -- and becomes the active one.
 ServerNow(function(rows)
  rows[2]={name='Fire PvE',verified=true,
   echoes={{spellId=201172,quality=0,stacks=2},{spellId=201175,quality=0,stacks=1}}}
  rows[1].name='One renamed'
  rows[3]={name='Arena 2',verified=true,echoes=H.Clone(REPLACED)}
 end)
 H.perks.serverActiveSlot=3;H.Notify();A.Poll();H.Advance(1)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','A16 said='..said..' facts='..Facts())
 C.guard(writes.SetLoadoutWishlist==1 and Writes()==1 and Stored(2)~=nil and Stored(2).name=='W-Free'
  and Stored(1)==nil and Stored(3)==nil,'A16: the unchanged named Saved Build 2 is assigned, once, and no other',Facts())
 C.guard(said:find("'W-Free' is now the Wishlist for Saved Build 'Fire PvE'",1,true)~=nil
  and said:find(CHANGED,1,true)==nil,'A16: it says so and reports no change',said)
 C.guard(Auto() and Settings()==settings and Creates()==0 and spends==0,'A16: Auto stays ON; no setting, upload or spend')
end)

C.scenario('A17 D7 control: the character check still comes first when the Saved Build changed as well',function()
 Boot()
 TurnAutoOn()
 local p=AskWFree('A17')
 C.setup(p~=nil,'A17: fixture: the click asks first')
 if not p then return end
 local facts=Facts()
 ServerNow(function(rows) rows[2]={name='Frost PvP',verified=true,echoes=H.Clone(REPLACED)} end)
 local store=Nexus.Store
 local key=store.CurrentOwnerKey
 store.CurrentOwnerKey=function() return 'someone-else@elsewhere' end
 local said=Heard(function() Accept(p) end)
 store.CurrentOwnerKey=key
 C.guard(Writes()==0 and Facts()==facts and said:find('Nothing was assigned',1,true)~=nil,
  'A17: the answer for another character assigns nothing and says why',said)
 C.guard(Auto(),'A17: Auto stays ON')
end)

C.scenario('A18 D7 a chooser left open over a replaced Saved Build asks nothing under the old name',function()
 Boot()
 TurnAutoOn()
 C.setup(Auto() and OpenPicker(),'A18: fixture: Auto is ON and the chooser is open for Saved Build 2 (Fire PvE)')
 local row=PickerRow('W-Free')
 C.setup(row~=nil,'A18: fixture: the chooser lists W-Free')
 if not row then return end
 local facts=Facts()
 -- Slot 2 is saved over while the chooser stays open.
 ServerNow(function(rows) rows[2]={name='Frost PvP',verified=true,echoes=H.Clone(REPLACED)} end)
 C.setup(NexusWishlistOnlyPicker:IsShown() and row:IsVisible(),'A18: fixture: the chooser is still open on its captured target')
 H.popup=nil
 local said=Heard(function() row.nameButton:Click() end)
 print('OBSERVED','A18 said='..said..' popup='..tostring(H.popup and Asked(H.popup)))
 C.expect(H.popup==nil and Refused(said),'A18: no question is asked under the old name; the player is told to choose again',said)
 C.guard(Writes()==0 and Facts()==facts and Auto(),'A18: nothing is assigned; Auto stays ON',Facts())
end)

-- Review F-5: the same identity also covers the click that assigns at once.
-- With Auto OFF no question waits, but a chooser left open still shows the
-- Saved Build it was opened for. EXPECT fails on the pin 6950edb3 by design
-- (the click wrote the captured slot and the line named the old build). The
-- unchanged-target control with Auto OFF is A7.
C.scenario('A19 F-5 Auto OFF: a chooser left open over a replaced Saved Build assigns nothing under the old name; choosing again assigns the current one',function()
 Boot()
 C.setup(not Auto() and OpenPicker(),'A19: fixture: Auto is OFF and the chooser is open for Saved Build 2 (Fire PvE)')
 local row=PickerRow('W-Free')
 C.setup(row~=nil,'A19: fixture: the chooser lists W-Free')
 if not row then return end
 local facts,settings=Facts(),Settings()
 -- Slot 2 is saved over while the chooser stays open.
 ServerNow(function(rows) rows[2]={name='Frost PvP',verified=true,echoes=H.Clone(REPLACED)} end)
 C.setup(NexusWishlistOnlyPicker:IsShown() and row:IsVisible(),'A19: fixture: the chooser is still open on its captured target')
 H.popup=nil
 local said=Heard(function() row.nameButton:Click() end)
 print('OBSERVED','A19 said='..said..' facts='..Facts())
 C.expect(H.popup==nil and Writes()==0 and Facts()==facts and Stored(2)==nil,
  'A19: the click for the replaced Saved Build calls no writer and stores nothing',Facts())
 C.expect(Refused(said) and not NexusWishlistOnlyPicker:IsShown(),
  'A19: the player is told to choose again and the stale chooser is closed',said)
 -- Choosing again assigns at once, to what the slot holds now, as Auto OFF does.
 C.setup(OpenPicker(),'A19b: fixture: the chooser is opened again')
 row=PickerRow('W-Free')
 C.setup(row~=nil,'A19b: fixture: the chooser lists W-Free')
 if not row then return end
 H.popup=nil
 said=Heard(function() row.nameButton:Click() end)
 print('OBSERVED','A19b said='..said..' facts='..Facts())
 C.expect(H.popup==nil and writes.SetLoadoutWishlist==1 and Writes()==1 and Stored(2)~=nil and Stored(2).name=='W-Free'
  and said:find("'W-Free' is now the Wishlist for Saved Build 'Frost PvP'",1,true)~=nil,
  'A19b: one more click assigns W-Free to the current Saved Build 2 without a question and names it',said)
 C.guard(not Auto() and Settings()==settings and Creates()==0 and spends==0,'A19: Auto stays OFF; no setting, upload or spend')
end)

-- D7 (N-4): the editor's Save & assign of a new plan is bound to the Saved
-- Build its draft captured (slot, name and contents), not to the slot number.
-- Saved over or renamed between the capture, the confirmation and the accept:
-- nothing is uploaded or assigned, and saving again asks for the Saved Build
-- the slot holds now. EXPECT here fails on the pin fccc12f5 by design (the
-- accept compared the slot number, the assignment tokens and "holds Echoes"
-- only, so the replacement received the Wishlist under the old name). GUARD
-- holds on both: gone, empty and unreadable were already refused before the
-- upload; the same Saved Build, another active slot, the first-run target and
-- Save changes keep their behaviour. The spaced retry is ux_save_retry_intent
-- R9/R10. Real editor controls and StaticPopup handlers; no native claim.
local function NotSaved(said)
 return said:find('Not saved',1,true)~=nil and said:find('Nothing was uploaded',1,true)~=nil
end
-- A new draft for the active Saved Build 2 and its Create & assign question.
local function AskCreate(tag,name)
 NewDraft(name)
 local p=Apply()
 C.setup(p~=nil and type(p.data)=='table' and type(p.data.confirmation)=='table'
  and p.data.confirmation.intent=='saveAndAssign' and p.data.confirmation.destinationKey=='savedBuild:2',
  tag..': fixture: Create & assign asks, bound to Saved Build 2')
 return p
end

C.scenario('B1 N-4 Save & assign, Auto ON: Saved Build 2 was replaced after the confirmation: nothing is uploaded or assigned; saving again asks for the build there now',function()
 Boot()
 TurnAutoOn()
 local p=AskCreate('B1','N4 replaced')
 if not p then return end
 C.setup(V.Names(Asked(p) or '','Fire PvE'),'B1: fixture: the confirmation names Fire PvE')
 local facts,settings=Facts(),Settings()
 ServerNow(function(rows) rows[2]={name='Frost PvP',verified=true,echoes=H.Clone(REPLACED)} end)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','B1 said='..said..' creates='..Creates()..' facts='..Facts())
 C.expect(Creates()==0 and Writes()==0 and Facts()==facts and Stored(2)==nil,
  'B1: the answer for the replaced Saved Build uploads nothing and assigns nothing',Facts())
 C.expect(NotSaved(said),'B1: it says not saved and that nothing was uploaded or assigned',said)
 C.guard(Auto() and Settings()==settings and spends==0,'B1: Auto stays ON; no setting or spend')
 -- Saving again offers a new confirmation naming what slot 2 holds now.
 local again=Apply()
 local asked=Asked(again)
 print('OBSERVED','B1b confirmation='..tostring(asked))
 C.expect(again~=nil and again~=p and asked~=nil and V.Names(asked,'Frost PvP') and not V.Names(asked,'Fire PvE')
  and again.data.confirmation.destinationKey=='savedBuild:2',
  'B1b: saving again asks for Saved Build 2 as it is now, by its current name',asked)
 if not again then return end
 Accept(again)
 C.expect(Creates()==1 and writes.SetLoadoutWishlistIdentity==1 and Writes()==1 and Stored(2)~=nil
  and Stored(2).name=='N4 replaced' and Stored(3)==nil,'B1b: that answer uploads once and assigns Saved Build 2',Facts())
end)

C.scenario('B2 N-4 Save & assign: the same slot and name with other contents is not the Saved Build that was confirmed',function()
 Boot()
 local p=AskCreate('B2','N4 contents')
 if not p then return end
 local facts=Facts()
 ServerNow(function(rows) rows[2]={name='Fire PvE',verified=true,
  echoes={{spellId=201175,quality=0,stacks=2},{spellId=201172,quality=0,stacks=1}}} end)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','B2 said='..said..' creates='..Creates()..' facts='..Facts())
 C.expect(Creates()==0 and Writes()==0 and Facts()==facts and Stored(2)==nil,
  'B2: an equal name and slot do not stand in for the Saved Build: nothing is uploaded or assigned',Facts())
 C.expect(NotSaved(said),'B2: it says not saved',said)
end)

C.scenario('B3 N-4 Save & assign: the confirmed Saved Build was renamed before the accept',function()
 Boot()
 local p=AskCreate('B3','N4 renamed')
 if not p then return end
 local facts=Facts()
 ServerNow(function(rows) rows[2].name='Fire Raid' end)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','B3 said='..said..' creates='..Creates()..' facts='..Facts())
 C.expect(Creates()==0 and Writes()==0 and Facts()==facts and Stored(2)==nil and NotSaved(said),
  'B3: nothing is uploaded or assigned under the old name',said)
end)

C.scenario('B4 N-4 Save & assign: Saved Build 2 was replaced after the draft began: no confirmation under the old name; the next one names the build there now',function()
 Boot()
 NewDraft('N4 early')
 local facts=Facts()
 ServerNow(function(rows) rows[2]={name='Frost PvP',verified=true,echoes=H.Clone(REPLACED)} end)
 local p
 local said=Heard(function() p=Apply() end)
 print('OBSERVED','B4 said='..said..' confirmation='..tostring(p and Asked(p)))
 C.expect(p==nil and NotSaved(said) and Creates()==0 and Writes()==0 and Facts()==facts,
  'B4: no confirmation is offered for the Saved Build the draft no longer matches; nothing is sent',said)
 local again=Apply()
 local asked=Asked(again)
 C.expect(again~=nil and asked~=nil and V.Names(asked,'Frost PvP') and not V.Names(asked,'Fire PvE'),
  'B4: the next attempt asks for Saved Build 2 as it is now',asked)
 if not again then return end
 Accept(again)
 C.expect(Creates()==1 and writes.SetLoadoutWishlistIdentity==1 and Stored(2)~=nil and Stored(2).name=='N4 early',
  'B4: that answer uploads once and assigns Saved Build 2',Facts())
end)

C.scenario('B5 N-4 controls: gone, empty or unreadable at the accept sends nothing (as before); the same Saved Build re-sent is assigned',function()
 Boot()
 local world=H.Clone(H.perks.serverBuildSlots)
 local function Restore() H.perks.serverBuildSlots=H.Clone(world);H.Notify();A.Poll();H.Advance(1) end
 NewDraft('N4 controls')
 local cases={
  {'gone',function() ServerNow(function(rows) rows[2]=nil end) end},
  {'empty',function() ServerNow(function(rows) rows[2]={name='Fire PvE',verified=true,echoes={}} end) end},
  {'unreadable',function() H.perks.serverBuildSlots=nil end},
 }
 for _,case in ipairs(cases) do
  local tag='B5 '..case[1]
  local p=Apply()
  C.setup(p~=nil,tag..': fixture: Create & assign asks')
  if not p then return end
  local facts=Facts()
  case[2]()
  local said=Heard(function() Accept(p) end)
  print('OBSERVED',tag..' said='..said..' creates='..Creates())
  C.guard(Creates()==0 and Writes()==0 and Facts()==facts and Stored(2)==nil,
   tag..': nothing is uploaded or assigned',Facts())
  Restore()
 end
 -- The same Saved Build 2 arrives again in fresh tables; other slots change.
 local p=Apply()
 C.setup(p~=nil,'B5 same: fixture: Create & assign asks')
 if not p then return end
 ServerNow(function(rows)
  rows[2]={name='Fire PvE',verified=true,echoes={{spellId=201175,quality=0,stacks=1}}}
  rows[1].name='One renamed'
  rows[3]={name='Arena 2',verified=true,echoes=H.Clone(REPLACED)}
 end)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','B5 same said='..said..' facts='..Facts())
 C.guard(Creates()==1 and writes.SetLoadoutWishlistIdentity==1 and Writes()==1 and Stored(2)~=nil
  and Stored(2).name=='N4 controls' and Stored(1)==nil and Stored(3)==nil,
  'B5 same: the unchanged Saved Build 2 is assigned, once, and no other',Facts())
end)

C.scenario('B6 N-4 control: another Saved Build becoming active does not retarget or stop the captured destination',function()
 Boot()
 local p=AskCreate('B6','N4 active')
 if not p then return end
 H.perks.serverActiveSlot=3;H.Notify();A.Poll();H.Advance(1)
 local said=Heard(function() Accept(p) end)
 print('OBSERVED','B6 said='..said..' facts='..Facts())
 C.guard(Creates()==1 and writes.SetLoadoutWishlistIdentity==1 and Writes()==1 and Stored(2)~=nil
  and Stored(2).name=='N4 active' and Stored(3)==nil,'B6: the captured Saved Build 2 is assigned, not the active one',Facts())
end)

C.scenario('B7 N-4 control: the first-run target carries no Saved Build identity and is unaffected by slot changes',function()
 Boot()
 H.perks.serverActiveSlot=0;H.Notify();A.Poll();H.Advance(1)
 NewDraft('N4 first')
 local p=Apply()
 ServerNow(function(rows) rows[2]={name='Frost PvP',verified=true,echoes=H.Clone(REPLACED)} end)
 if p then Accept(p) end
 local first=Nexus.Store.State().firstRunWishlist
 print('OBSERVED','B7 creates='..Creates()..' facts='..Facts())
 C.guard(Creates()==1 and type(first)=='table' and first.name=='N4 first' and Stored(2)==nil and Stored(3)==nil,
  'B7: the new plan is uploaded once and is the first-run target; no Saved Build is assigned',Facts())
end)

C.scenario('B8 N-4 control: Save changes (Create unassigned) writes no destination, so a replaced Saved Build does not stop it',function()
 Boot()
 NewDraft('N4 unassigned')
 local facts=Facts()
 ServerNow(function(rows) rows[2]={name='Frost PvP',verified=true,echoes=H.Clone(REPLACED)} end)
 local only=EditorButton('Create unassigned')
 local p=Click(only)
 C.setup(p~=nil,'B8: fixture: Create unassigned asks for confirmation')
 if not p then return end
 Accept(p)
 print('OBSERVED','B8 creates='..Creates()..' facts='..Facts())
 C.guard(Creates()==1 and Writes()==0 and Facts()==facts,'B8: it uploads once and writes no destination',Facts())
end)

C.finish('(Save & assign names its captured destination and Auto\'s existing consequence; cancel/stale/Save changes write none; the Auto-ON picker asks first)')
