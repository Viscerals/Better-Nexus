-- M7 (UX setup checklist; journeys J1/J2): a read-only "Setup checklist and
-- status" window, reached from Help's action row and the Nexus panel's ...
-- menu. Its steps (start-up, the destination Nexus would act on, its assigned
-- Wishlist) are worded by UserText from Panel.SetupFacts, from current facts
-- only. Loading, restoring, unavailable and not-known stay apart from done;
-- an empty Saved Build is not unassigned. Whether the Welcome was seen or
-- closed, and the Auto warning's answer, are never setup facts. Its buttons
-- only navigate through Help's routes: none assigns, saves, sends, turns Auto
-- ON, starts or resumes an Orb run or spends.
-- Categories (view_regression_support): EXPECT is behaviour added in M7 (it is
-- predicted to fail on accepted M6 0924d06a, where the checklist does not
-- exist; not executed by the author). A missing checklist is reported as a
-- failed EXPECT, never as a raised scenario. GUARD already holds there and
-- must keep holding; SETUP is the fixture.
-- Oracles: the real checklist window and its fontstrings, UserText's pure
-- wording functions, Help's real routes, the panel's real ... menu items
-- (EasyMenu observed at its boundary), and the counted assignment writers,
-- game actions, sends and requests. Real TOC boot, adapter, runtime and panel;
-- synthetic host services only. No native claim.
-- J2 (M7 step 1, issue #131): one measured real-handler journey from an
-- existing Saved Build with no assignment, through the live checklist (the
-- ... menu route), its Assign Wishlist... route to the Echo Journal chooser,
-- a cancel, the deliberate choice of the existing Wishlist and the
-- checklist/status readback, then one destination change while the chooser
-- is open (no chooser callback is delivered there). Each no-side-effect
-- frontier is measured on its own: passive navigation/cancel, the explicit
-- assignment (one association write only) and the later passive refreshes.
-- J2b (fresh boot) measures the delayed chooser callback: a visible,
-- unassigned candidate's production OnClick is captured before the
-- destination change and delivered once afterwards, as a SYNTHETIC
-- queued-callback boundary (no native timing or visible-click claim).
-- J2c (fresh boot) checks that the J2b oracle rejects a skipped delivery and
-- a write routed to another Saved Build. Pass-through spies only, apart from
-- J2c's isolated test-only fault router.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_setup_checklist')
local H,A,writes
local E1={{spellId=201172,quality=0,stacks=1}}
local E2={{spellId=201175,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist',
 'ClearFirstRunWishlist','SetFirstRunWishlistIdentity'}

local function Boot(active)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;EchoJournalMicroButton=nil
 NexusEditorFrame=nil;NexusWishlistNameInput=nil;NexusPanel=nil;NexusHelpWindow=nil;NexusSetupChecklist=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 wipe(H.db)
 H.AddEcho(201172,'Echo One',0,5);H.AddEcho(201174,'Echo Free',0,5);H.AddEcho(201175,'Echo Fire',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots={[1]={name='One',verified=true,echoes=E1},[2]={name='Fire PvE',verified=true,echoes=E2},
  [3]={name='Empty three',verified=true,echoes={}},[107]={name='W-Free',verified=false,echoes=EF}}
 H.perks.serverActiveSlot=active
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function() error('the setup checklist must not spend') end}
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
local function Writes() local n=0;for _,c in pairs(writes) do n=n+c end;return n end
local function Auto() return Nexus.RecomputeStats().autoEnabled==true end
local function Effects()
 return {writes=Writes(),actions=#H.actions,sent=#H.sent,granted=tonumber(H.grantedRequests) or 0,auto=Auto(),
  orb=Nexus.OrbRuntime.Status().running==true,seen=type(NexusDB)=='table' and rawget(NexusDB,'hasSeenQuickStart') or nil}
end
local function Same(a,b)
 return a.writes==b.writes and a.actions==b.actions and a.sent==b.sent and a.granted==b.granted
  and a.auto==b.auto and a.orb==b.orb and a.seen==b.seen
end
local function Describe(e)
 return 'writes='..e.writes..' actions='..e.actions..' sent='..e.sent..' granted='..e.granted
  ..' auto='..tostring(e.auto)..' orb='..tostring(e.orb)..' seen='..tostring(e.seen)
end
local function Refresh()
 Nexus.Panel.Show()
 if Nexus.RequestRecompute then Nexus.RequestRecompute() end
 H.Notify();A.Poll();H.Advance(1)
 return Nexus.Panel._lastModel
end
-- The checklist window, opened through QuickStart.ShowChecklist when it exists.
local function Open(tag)
 local quick=Nexus.QuickStart
 local show=quick and quick.ShowChecklist
 C.expect(type(show)=='function',tag..': the setup checklist can be opened')
 if type(show)~='function' then return nil end
 local f=show()
 C.expect(f~=nil and f==_G.NexusSetupChecklist and f:IsShown(),tag..': the checklist window is shown')
 return f
end
local function Rows(f)
 local out={}
 for i,line in ipairs(f.rows or {}) do out[i]=V.Plain(line:GetText() or '') end
 return out
end
local function Status(f)
 local out={}
 for i,line in ipairs(f.status or {}) do out[i]=V.Plain(line:GetText() or '') end
 return out
end
local function Has(text,needle) return tostring(text or ''):find(needle,1,true)~=nil end

C.scenario('K1 an active Saved Build with an assigned Wishlist: every step is done now',function()
 Boot(2)
 C.setup(A.SetLoadoutWishlist(2,107)==true,'K1: fixture: Saved Build 2 (Fire PvE) is assigned W-Free')
 local model=Refresh()
 C.setup(type(model)=='table' and type(model.assignment)=='table' and model.assignment.state=='ready',
  'K1: fixture: the runtime published a ready assignment',type(model)=='table' and type(model.assignment)=='table' and model.assignment.state)
 local before=Effects()
 local f=Open('K1')
 if not f then return end
 local rows=Rows(f)
 print('OBSERVED','K1 rows='..table.concat(rows,' / ')..' summary='..V.Plain(f.summary:GetText()))
 C.expect(Has(rows[1],'[done] Start-up'),'K1: start-up is done',rows[1])
 C.expect(Has(rows[2],'[done] Destination') and Has(rows[2],"Saved Build 'Fire PvE' (slot 2)") and Has(rows[2],'active in the game'),
  'K1: the destination names the active Saved Build',rows[2])
 C.expect(Has(rows[3],'[done] Wishlist') and Has(rows[3],"'W-Free' is assigned"),'K1: its Wishlist is assigned',rows[3])
 C.expect(Has(f.summary:GetText(),'3 of 3') and f.steps and f.steps.complete==true,'K1: all three steps are done now',f.summary:GetText())
 local status=Status(f)
 C.expect(Has(status[1],'Auto: OFF') and Has(status[2],'Sync:') and Has(status[3],'Orbs (optional): no Orb run approved this session'),
  'K1: Auto OFF, the Sync mode and no Orb run are stated as status, not steps',table.concat(status,' / '))
 C.guard(Same(Effects(),before),'K1: opening the checklist writes, acts, sends and requests nothing',Describe(Effects()))
 -- Escape closes it: registered once, also when opened again.
 Nexus.QuickStart.ShowChecklist();Nexus.QuickStart.ShowChecklist()
 local n=0;for _,name in ipairs(UISpecialFrames) do if name=='NexusSetupChecklist' then n=n+1 end end
 C.expect(n==1,'K1: Escape closes the checklist (registered once)',n)
end)

C.scenario('K2 an unassigned Saved Build: the Wishlist step is to do, nothing is complete',function()
 Boot(1)
 local model=Refresh()
 C.setup(type(model)=='table' and model.assignment and model.assignment.state=='unassigned','K2: fixture: Saved Build 1 has no assignment')
 local f=Open('K2')
 if not f then return end
 local rows=Rows(f)
 print('OBSERVED','K2 rows='..table.concat(rows,' / '))
 C.expect(Has(rows[2],'[done] Destination') and Has(rows[2],"Saved Build 'One' (slot 1)"),'K2: the destination is known',rows[2])
 C.expect(Has(rows[3],'[to do] Wishlist') and Has(rows[3],'None assigned') and Has(rows[3],'nothing is assigned until you choose'),
  'K2: the Wishlist step is to do, and says the chooser assigns nothing by itself',rows[3])
 C.expect(f.steps and f.steps.complete==false and Has(f.summary:GetText(),'2 of 3')
  and Has(f.summary:GetText(),'Nothing here completes a step for you'),'K2: setup is not complete',f.summary:GetText())
end)

C.scenario('K3 an empty Saved Build is a step to do, not an unassigned or done one',function()
 Boot(3)
 local model=Refresh()
 C.setup(type(model)=='table' and model.assignment and model.assignment.emptySlot==true,'K3: fixture: the active Saved Build 3 holds no Echoes')
 local f=Open('K3')
 if not f then return end
 local rows=Rows(f)
 print('OBSERVED','K3 rows='..table.concat(rows,' / '))
 C.expect(Has(rows[2],'[to do] Destination') and Has(rows[2],'holds no Echoes'),'K3: the empty Saved Build is named as the step to fix',rows[2])
 C.expect(not Has(rows[3],'None assigned') and not Has(rows[3],'[done]'),'K3: it is not called unassigned or done',rows[3])
end)

C.scenario('K4 the Welcome and the Auto warning are never setup facts',function()
 Boot(2)
 C.setup(A.SetLoadoutWishlist(2,107)==true,'K4: fixture: Saved Build 2 is assigned W-Free')
 Refresh()
 local f=Open('K4')
 if not f then return end
 NexusDB.hasSeenQuickStart=nil;Nexus.QuickStart.RefreshChecklist()
 local unseen=table.concat(Rows(f),' / ')..V.Plain(f.summary:GetText())
 NexusDB.hasSeenQuickStart=true;Nexus.QuickStart.RefreshChecklist()
 local seen=table.concat(Rows(f),' / ')..V.Plain(f.summary:GetText())
 C.expect(unseen==seen and unseen~='','K4: the steps read the same whether or not the Welcome was seen',unseen..' || '..seen)
 -- The checklist part of QuickStart reads neither the Welcome nor the warning.
 local handle=assert(io.open('ui/QuickStart.lua','rb'));local src=handle:read('*a');handle:close()
 local first=src:find('M7: Setup checklist and status',1,true)
 local last=src:find('function M.ShowIfFirstTime',1,true)
 local part=first and last and src:sub(first,last) or ''
 C.expect(part~='' and not Has(part,'hasSeenQuickStart') and not Has(part,'OverwriteWarning') and not Has(part,'dismissed'),
  'K4: the checklist code reads no Welcome, dismissal or warning state',#part)
 local okUser,steps=pcall(function() return Nexus.UserText.SetupChecklist({startup='ready',hasSeenQuickStart=true,welcomeClosed=true}) end)
 C.expect(okUser and type(steps)=='table' and steps.complete==false,'K4: Welcome facts alone never complete setup',okUser and steps and tostring(steps.complete))
end)

C.scenario('K5 unknown, loading, restoring and unavailable stay apart from done',function()
 Boot(2)
 local T=Nexus.UserText
 C.expect(type(T.SetupChecklist)=='function' and type(T.StatusLines)=='function','K5: the checklist wording exists')
 if type(T.SetupChecklist)~='function' or type(T.StatusLines)~='function' then return end
 local function statuses(f)
  local s=T.SetupChecklist(f);local out={}
  for i,row in ipairs(s.rows) do out[i]=row.status end
  return table.concat(out,','),s.complete
 end
 local cases={
  {'nothing readable',{},'unknown,unknown,unknown'},
  {'start-up loading',{startup='loading'},'waiting,unknown,unknown'},
  {'no panel model yet',{startup='ready'},'done,unknown,unknown'},
  {'restoring',{startup='ready',destination={kind='unknown',reason='restoring',wishlistState='restoring'}},'done,waiting,waiting'},
  {'unavailable assignment',{startup='ready',destination={kind='savedBuild',slot=2,name='X',active=true,wishlistState='unavailable',wishlist='Lost'}},'done,done,unknown'},
  {'unconfirmed Saved Build',{startup='ready',destination={kind='savedBuild',unconfirmed=true,wishlistState='assigned',wishlist='W'}},'done,unknown,done'},
  {'first-run target',{startup='ready',destination={kind='firstRun',wishlistState='assigned',wishlist='W'}},'done,done,done'},
 }
 for _,case in ipairs(cases) do
  local got,complete=statuses(case[2])
  C.expect(got==case[3],'K5: '..case[1]..' reads '..case[3],got)
  C.expect(complete==(case[3]=='done,done,done'),'K5: '..case[1]..' is complete only when every step is done',tostring(complete))
 end
 local lines=T.StatusLines({})
 C.expect(Has(lines[1],'not known') and Has(lines[2],'not known') and Has(lines[3],'not known'),
  'K5: unread Auto, Sync and Orb facts say not known',table.concat(lines,' / '))
 lines=T.StatusLines({auto=false,syncMode='off',orb=false})
 C.expect(Has(lines[1],'Auto: OFF') and Has(lines[2],'Sync: Off') and Has(lines[3],'no Orb run'),
  'K5: OFF, Off and no run are answers, not unknown',table.concat(lines,' / '))
end)

C.scenario('K6 its buttons and routes only navigate',function()
 Boot(1)
 Refresh()
 -- The Journal route's endpoint is observed at its boundary (the game's
 -- Character Progression window is not modelled here): counted, not opened.
 local journal=Nexus.JournalTab
 local opened=0
 if journal then
  journal.OpenBuilds=function() opened=opened+1 end
  journal.CanOpenBuilds=function() return true end
 end
 local before=Effects()
 local f=Open('K6')
 if not f then return end
 C.expect(f.assign and V.Plain(f.assign:GetText())=='Assign Wishlist...' and f.editor and V.Plain(f.editor:GetText())=='Wishlist Editor'
  and f.help and f.close,'K6: Assign Wishlist..., Wishlist Editor, Help and Close are offered')
 f.assign:Click()
 C.expect(opened==1 and not f:IsShown(),'K6: Assign Wishlist... opens the Wishlist chooser route once and closes the checklist',opened)
 f=Nexus.QuickStart.ShowChecklist()
 f.editor:Click()
 C.expect(_G.NexusEditorFrame~=nil and NexusEditorFrame:IsShown(),'K6: Wishlist Editor opens the editor')
 if NexusEditorFrame then NexusEditorFrame:Hide() end
 f=Nexus.QuickStart.ShowChecklist()
 f.help:Click()
 C.expect(_G.NexusHelpWindow~=nil and NexusHelpWindow:IsShown() and V.Plain(NexusHelpWindow.page:GetText())=='Page 1 / 7',
  'K6: Help opens Getting started')
 f.close:Click()
 C.guard(not f:IsShown(),'K6: Close hides the checklist')
 C.guard(Writes()==before.writes and #H.actions==before.actions and #H.sent==before.sent and Auto()==before.auto
  and not Nexus.OrbRuntime.Status().running,'K6: no route assigned, acted, sent, turned Auto ON or started an Orb run',Describe(Effects()))
 -- Help's action row and the panel's ... menu reach the same window.
 Nexus.Help.Show('start')
 local button=V.Button(H,NexusHelpWindow,'Setup checklist')
 C.expect(button~=nil,'K6: Help offers Setup checklist on its action row')
 if button then
  Nexus.QuickStart.HideChecklist();button:Click()
  C.expect(NexusSetupChecklist:IsShown() and not NexusHelpWindow:IsShown(),'K6: Help\'s Setup checklist opens it in place of Help')
 end
 local items
 local realEasy,realClose=EasyMenu,CloseDropDownMenus
 EasyMenu=function(list) items=list end;CloseDropDownMenus=function() end
 local menu=NexusPanel and NexusPanel._menuBtn
 if menu then menu:GetScript('OnClick')(menu) end
 EasyMenu,CloseDropDownMenus=realEasy,realClose
 local entry
 for _,item in ipairs(items or {}) do if item.text=='Setup checklist and status' then entry=item end end
 C.expect(entry~=nil and type(entry.func)=='function','K6: the ... menu offers Setup checklist and status')
 if entry then
  Nexus.QuickStart.HideChecklist();CloseDropDownMenus=function() end
  entry.func()
  CloseDropDownMenus=realClose
  C.expect(NexusSetupChecklist:IsShown(),'K6: the menu item opens the checklist')
 end
 C.guard(Writes()==before.writes and #H.actions==before.actions and #H.sent==before.sent and Auto()==before.auto,
  'K6: opening it from Help or the menu changes nothing',Describe(Effects()))
end)

-- Continuation 48 (UX-18, approved "Escape closes Welcome"). FrameXML's Escape
-- handler (UIParent CloseSpecialWindows) hides each shown frame named in
-- UISpecialFrames and reports whether one was; it is modeled here, in this
-- test, with the real QuickStart frames and registrations. This is not a
-- native key press or keyboard/focus observation (M8). EXPECT: added here
-- (on the exact 8be cut the Welcome has no Escape closure, so these are
-- predicted to fail there); GUARD: already holds there and must keep holding.
-- Returns the set of names it hid (other shown special frames, such as a
-- window the boot left open, are hidden too, as in the client).
local function Escape()
 local hid={}
 for _,name in ipairs(UISpecialFrames) do
  local f=_G[name]
  if f and f.IsShown and f:IsShown() then f:Hide();hid[name]=true end
 end
 return hid
end
local function Welcome() return _G.NexusQuickStart end
local function Seen() return type(NexusDB)=='table' and rawget(NexusDB,'hasSeenQuickStart') or nil end
local function Quiet(before)
 return Writes()==before.writes and #H.actions==before.actions and #H.sent==before.sent and Auto()==before.auto
  and not Nexus.OrbRuntime.Status().running
end

C.scenario('K7 Escape closes the first-time Welcome as Close does; an ordinary hide still records nothing',function()
 Boot(2)
 C.setup(Seen()==nil,'K7: fixture: the Welcome has not been acknowledged',tostring(Seen()))
 Nexus.QuickStart.ShowIfFirstTime()
 local w=Welcome()
 C.setup(w~=nil and w:IsShown() and V.Plain(w.title:GetText() or '')=='Welcome to Nexus','K7: fixture: the first-time Welcome is shown')
 if not (w and w:IsShown()) then return end
 local before=Effects()
 -- An ordinary hide, as the HUD's CloseOtherNexusWindows does.
 w:Hide()
 C.guard(Seen()==nil,'K7: an ordinary hide records no acknowledgement')
 local idle=Escape()
 C.guard(not idle.NexusQuickStartEscape and not idle.NexusQuickStart and not w:IsShown() and Seen()==nil,
  'K7: an Escape while the Welcome is closed takes no Welcome entry and records nothing')
 Nexus.QuickStart.ShowIfFirstTime()
 C.guard(w:IsShown(),'K7: after an ordinary hide the first-time Welcome is offered again')
 Nexus.QuickStart.ShowIfFirstTime()
 local registered=0
 for _,name in ipairs(UISpecialFrames) do if name=='NexusQuickStartEscape' then registered=registered+1 end end
 C.expect(registered==1,'K7: the Welcome is reachable by Escape, registered once',registered)
 local closed=Escape()
 C.expect(closed.NexusQuickStartEscape==true and not w:IsShown(),'K7: Escape closes the first-time Welcome')
 local settled=Nexus.QuickStart.ShowIfFirstTime()
 C.expect(not w:IsShown(),'K7: after Escape the Welcome is not offered again this session',tostring(settled))
 local durable=Nexus.QuickStart.CanRecordSeen()
 C.expect((durable and Seen()==true and settled==true) or (not durable and Seen()==nil),
  'K7: the acknowledgement follows Close\'s policy (recorded only when it can be saved)',
  'durable='..tostring(durable)..' seen='..tostring(Seen())..' settled='..tostring(settled))
 C.guard(Quiet(before),'K7: closing the Welcome assigns, acts, sends, turns Auto ON and starts nothing',Describe(Effects()))
end)

C.scenario('K8 Escape closes the informational Setup / Welcome with no write; the first-time Welcome stays offered',function()
 Boot(2)
 C.setup(Seen()==nil,'K8: fixture: the Welcome has not been acknowledged',tostring(Seen()))
 local shown,why=Nexus.QuickStart.ShowSetup()
 local w=Welcome()
 C.setup(shown==true and w~=nil and w:IsShown() and V.Plain(w.title:GetText() or '')=='Nexus setup (information only)',
  'K8: fixture: the informational replay is shown',tostring(why))
 if not (w and w:IsShown()) then return end
 local before=Effects()
 local closed=Escape()
 C.expect(closed.NexusQuickStartEscape==true and not w:IsShown(),'K8: Escape closes the informational replay')
 C.guard(Seen()==nil and Quiet(before),'K8: closing the replay writes no acknowledgement and acts on nothing',Describe(Effects()))
 Nexus.QuickStart.ShowIfFirstTime()
 C.guard(w:IsShown() and V.Plain(w.title:GetText() or '')=='Welcome to Nexus',
  'K8: the first-time Welcome is still offered afterwards: the replay dismissed nothing')
end)

-- Continuation 50 (review36 M7R-01): a passive ancestor hide (the UI hidden,
-- a cinematic) must neither close nor acknowledge the Welcome. SYNTHETIC
-- ancestor-visibility model, local to this test; the shared harness is
-- unchanged. In the client, hiding an ancestor fires OnHide on each shown
-- descendant that stops being visible, and showing it fires OnShow on each one
-- that becomes visible again; the harness Hide/Show fire only the frame's own
-- script, while its IsVisible is parent-aware. The model walks the Welcome's
-- own subtree once (finite), records visibility, flips the ancestor, then
-- fires the recorded frames' own scripts, parent before child. Limits: only
-- the Welcome subtree is fired (other windows' hide effects are outside this
-- test), and the Escape child's OnHide may run twice (the Welcome's own hook,
-- then the walk). This is not a native observation (M8 NOT_RUN).
-- EXPECT: added here (on exact 03c0 the Escape entry finishes on IsShown, so
-- the propagated OnHide closes the Welcome and they are predicted to fail
-- there; not executed by the author); GUARD and SETUP hold there too.
local function Subtree(root,out)
 out=out or {root}
 for _,c in ipairs(root.children or {}) do out[#out+1]=c;Subtree(c,out) end
 return out
end
local function AncestorHide(ancestor,subtree)
 local was={}
 for _,d in ipairs(Subtree(subtree)) do if d:IsVisible() then was[#was+1]=d end end
 ancestor:Hide()
 local fired=0
 for _,d in ipairs(was) do
  if not d:IsVisible() and d.scripts and d.scripts.OnHide then d.scripts.OnHide(d);fired=fired+1 end
 end
 return fired
end
local function AncestorShow(ancestor,subtree)
 local hidden={}
 for _,d in ipairs(Subtree(subtree)) do if not d:IsVisible() then hidden[#hidden+1]=d end end
 ancestor:Show()
 for _,d in ipairs(hidden) do
  if d:IsVisible() and d.scripts and d.scripts.OnShow then d.scripts.OnShow(d) end
 end
end

C.scenario('K9 a passive ancestor hide neither closes nor acknowledges the first-time Welcome; Escape still does',function()
 Boot(2)
 C.setup(Seen()==nil,'K9: fixture: the Welcome has not been acknowledged',tostring(Seen()))
 Nexus.QuickStart.ShowIfFirstTime()
 local w,esc=Welcome(),_G.NexusQuickStartEscape
 C.setup(w~=nil and esc~=nil and w:IsVisible() and esc:IsShown() and V.Plain(w.title:GetText() or '')=='Welcome to Nexus',
  'K9: fixture: the first-time Welcome and its Escape entry are shown')
 if not (w and esc and w:IsVisible()) then return end
 -- An unrelated key reaches no QuickStart code: neither frame handles keys.
 C.guard(not w.scripts.OnKeyDown and not w.scripts.OnKeyUp and not w.scripts.OnChar
  and not esc.scripts.OnKeyDown and not esc.scripts.OnKeyUp and not esc.scripts.OnChar,
  'K9: no key handler on the Welcome or its Escape entry, so an unrelated key acknowledges nothing')
 local before=Effects()
 local fired=AncestorHide(UIParent,w)
 C.setup(fired>=2 and not w:IsVisible(),'K9: fixture (SYNTHETIC propagation): the UI root is hidden and the Welcome subtree got its OnHide',fired)
 C.expect(w:IsShown() and Seen()==nil,'K9: the passive hide neither closes the Welcome nor records an acknowledgement',
  'shown='..tostring(w:IsShown())..' seen='..tostring(Seen()))
 AncestorShow(UIParent,w)
 C.expect(w:IsVisible() and esc:IsShown(),'K9: when the UI is shown again the Welcome and its Escape entry are back')
 Nexus.QuickStart.ShowIfFirstTime()
 C.expect(w:IsShown() and Seen()==nil,'K9: it is still the unacknowledged first-time Welcome')
 local closed=Escape()
 local durable=Nexus.QuickStart.CanRecordSeen()
 C.expect(closed.NexusQuickStartEscape==true and not w:IsShown() and ((durable and Seen()==true) or (not durable and Seen()==nil)),
  'K9: an explicit Escape afterwards still closes it with Close\'s acknowledgement policy',
  'closed='..tostring(closed.NexusQuickStartEscape)..' durable='..tostring(durable)..' seen='..tostring(Seen()))
 C.guard(Quiet(before),'K9: nothing assigns, acts, sends, turns Auto ON or starts',Describe(Effects()))
end)

C.scenario('K10 a passive ancestor hide leaves the informational replay open and unwritten',function()
 Boot(2)
 C.setup(Seen()==nil,'K10: fixture: the Welcome has not been acknowledged',tostring(Seen()))
 local shown,why=Nexus.QuickStart.ShowSetup()
 local w=Welcome()
 C.setup(shown==true and w~=nil and w:IsVisible() and V.Plain(w.title:GetText() or '')=='Nexus setup (information only)',
  'K10: fixture: the informational replay is shown',tostring(why))
 if not (w and w:IsVisible()) then return end
 local before=Effects()
 local fired=AncestorHide(UIParent,w)
 C.setup(fired>=2 and not w:IsVisible(),'K10: fixture (SYNTHETIC propagation): the UI root is hidden',fired)
 C.expect(w:IsShown(),'K10: the passive hide does not close the replay')
 C.guard(Seen()==nil and Quiet(before),'K10: nothing is written or acted on',Describe(Effects()))
 AncestorShow(UIParent,w)
 C.expect(w:IsVisible() and V.Plain(w.title:GetText() or '')=='Nexus setup (information only)','K10: the replay is back, still information only')
 local closed=Escape()
 C.expect(closed.NexusQuickStartEscape==true and not w:IsShown() and Seen()==nil,'K10: an explicit Escape still closes it with no write')
end)

-- J2 journey (M7 step 1, issue #131 J2 sub-slice): an existing Saved Build
-- with no assignment reaches an assigned Wishlist through the live checklist
-- and its real chooser route, in one measured flow. Pass-through observation
-- only: no product method is replaced. The Echo Journal frame and the game's
-- Character Progression button are synthetic host frames, as in
-- ux_help_navigation; the Journal route, its chooser and its writer are real.
local J2_TITLE_SLOT={['Assign to: Fire PvE']=2,['Assign to: One']=1}
local J2_FIRE,J2_ONE="Saved Build 'Fire PvE' (slot 2)","Saved Build 'One' (slot 1)"
local function J2Host()
 local journal=_G.ProjectEbonholdEchoJournal or CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
 journal:Hide()
 local micro=_G.EchoJournalMicroButton or CreateFrame('Button','EchoJournalMicroButton',UIParent)
 micro:SetScript('OnClick',function() journal:Show() end)
 return journal
end
local function J2Chooser()
 local p=_G.NexusWishlistOnlyPicker
 return p~=nil and p:IsShown(),p and p.title and V.Plain(p.title:GetText() or '') or ''
end
local function J2CloseChooser()
 local p,s=_G.NexusWishlistOnlyPicker,_G.NexusActiveWishlistSelector
 if p and p:IsShown() and s then s:Click() end
end
local function J2Row(name)
 local p=_G.NexusWishlistOnlyPicker
 for _,row in ipairs(p and p.children or {}) do
  if row.nameButton and row:IsVisible() and V.Plain(tostring(row.nameButton.text:GetText() or '')):find(name,1,true) then return row end
 end
 return nil
end
local function J2Stored(slot)
 local s=Nexus.Store.State() or {}
 return type(s.loadoutWishlists)=='table' and s.loadoutWishlists[slot] or nil
end
local function J2Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 if not ok then error(err,0) end
 return V.Plain(table.concat(heard,' / '))
end
-- The side-effect counters of one frontier: every assignment writer call (and
-- the Saved Build of each SetLoadoutWishlist call), host uploads and adapter
-- upload calls, every other host action, sends, Auto, an Orb run and the
-- Welcome acknowledgement.
local function J2Frontier(J)
 local uploads,others=0,0
 for _,a in ipairs(H.actions) do if a[1]=='upload' then uploads=uploads+1 else others=others+1 end end
 local slots={}
 for k,v in pairs(J.slotWrites) do slots[#slots+1]=tostring(k)..':'..v end
 table.sort(slots)
 return {writes=Writes(),slots=table.concat(slots,','),uploads=uploads,uploadCalls=J.uploadCalls,others=others,
  sent=#H.sent,auto=Auto(),orb=Nexus.OrbRuntime.Status().running==true,
  seen=type(NexusDB)=='table' and rawget(NexusDB,'hasSeenQuickStart') or nil}
end
local function J2Describe(e)
 return 'writes='..e.writes..' slots=['..e.slots..'] uploads='..e.uploads..' uploadCalls='..e.uploadCalls
  ..' actions='..e.others..' sent='..e.sent..' auto='..tostring(e.auto)..' orb='..tostring(e.orb)
end
-- withSent: the frontier ran no harness time, so sends are comparable.
local function J2Unchanged(a,b,withSent)
 return a.writes==b.writes and a.slots==b.slots and a.uploads==b.uploads and a.uploadCalls==b.uploadCalls
  and a.others==b.others and a.auto==b.auto and a.orb==b.orb and a.seen==b.seen
  and (not withSent or a.sent==b.sent)
end
-- The readback oracle over the checklist's own rows: the captured destination
-- is active and done, and its assigned Wishlist is done.
local function J2Readback(rows,destination,wishlist)
 rows=type(rows)=='table' and rows or {}
 return Has(rows[2],'[done] Destination') and Has(rows[2],destination) and Has(rows[2],'active in the game')
  and Has(rows[3],'[done] Wishlist') and Has(rows[3],"'"..wishlist.."' is assigned")
end
-- The stale oracle after a context change: the row names the destination
-- Nexus acts on now, and its Wishlist is done exactly when that destination
-- holds an assignment (never on the strength of another Saved Build's).
local function J2Truthful(rows,destination,stored)
 rows=type(rows)=='table' and rows or {}
 if not (Has(rows[2],'[done] Destination') and Has(rows[2],destination)) then return false end
 if type(stored)=='table' then
  return Has(rows[3],'[done] Wishlist') and Has(rows[3],"'"..tostring(stored.name).."' is assigned")
 end
 return Has(rows[3],'[to do] Wishlist') and Has(rows[3],'None assigned') and not Has(rows[3],'[done]')
end
local function J2Settle(pred)
 local model
 for _=1,10 do model=Refresh();if pred(model) then return model,true end end
 return model,false
end
-- The ... menu's real "Setup checklist and status" item (EasyMenu observed at
-- its boundary, as in K6; both globals restored unconditionally). A missing
-- item is a failed EXPECT, and the journey then continues through the same
-- QuickStart entry that Help uses.
local function J2OpenViaMenu(tag)
 local items,opened
 local realEasy,realClose=EasyMenu,CloseDropDownMenus
 local ok,err=pcall(function()
  EasyMenu=function(list) items=list end
  CloseDropDownMenus=function() end
  local menu=NexusPanel and NexusPanel._menuBtn
  if menu and menu:GetScript('OnClick') then menu:GetScript('OnClick')(menu) end
  for _,item in ipairs(items or {}) do
   if item.text=='Setup checklist and status' and type(item.func)=='function' then
    if Nexus.QuickStart and Nexus.QuickStart.HideChecklist then Nexus.QuickStart.HideChecklist() end
    item.func();opened=true
   end
  end
 end)
 EasyMenu,CloseDropDownMenus=realEasy,realClose
 if not ok then error(err,0) end
 local f=_G.NexusSetupChecklist
 local shown=opened==true and f~=nil and f:IsShown()
 C.expect(shown,tag..': the ... menu item Setup checklist and status opens the live checklist')
 if shown then return f end
 return Open(tag..' (fallback: QuickStart.ShowChecklist)')
end

C.scenario('J2 an existing unassigned Saved Build reaches an assigned Wishlist through the checklist and its chooser',function()
 -- Matched discriminators first: this file's two journey oracles on synthetic
 -- rows, as fixture SETUP. They test the oracles (they hold on any cut), not
 -- the product; an EXPECT that uses a failed oracle is not evaluated.
 local x='[done] Start-up: Local saved data is restored.'
 local fireDone='[done] Destination: '..J2_FIRE..' is active in the game.'
 local oneDone='[done] Destination: '..J2_ONE..' is active in the game.'
 local freeDone="[done] Wishlist: 'W-Free' is assigned."
 local todo='[to do] Wishlist: None assigned. Assign Wishlist... opens the chooser; nothing is assigned until you choose.'
 local readbackOracle=C.setup(J2Readback({x,fireDone,freeDone},J2_FIRE,'W-Free') and not J2Readback({x,oneDone,freeDone},J2_FIRE,'W-Free')
  and not J2Readback({x,fireDone,todo},J2_FIRE,'W-Free'),
  'J2: fixture: oracle self-check (not product evidence): readback accepts the captured destination, rejects a wrong destination and an unassigned row; if it fails, the EXPECTs that use this oracle are not evaluated')
 local truthfulOracle=C.setup(J2Truthful({x,oneDone,todo},J2_ONE,nil) and not J2Truthful({x,oneDone,freeDone},J2_ONE,nil)
  and not J2Truthful({x,fireDone,freeDone},J2_ONE,nil) and J2Truthful({x,oneDone,freeDone},J2_ONE,{name='W-Free'}),
  'J2: fixture: oracle self-check (not product evidence): the stale oracle rejects a stale ready row for an unassigned current destination; if it fails, the EXPECT that uses this oracle is not evaluated')
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusLoadoutAssociationPanel=nil
 Boot(2)
 local J={slotWrites={},uploadCalls=0}
 local counted,realUpload=A.SetLoadoutWishlist,A.UploadWishlist
 A.SetLoadoutWishlist=function(slot,...)
  local k=tonumber(slot) or tostring(slot)
  J.slotWrites[k]=(J.slotWrites[k] or 0)+1
  return counted(slot,...)
 end
 A.UploadWishlist=function(...) J.uploadCalls=J.uploadCalls+1;return realUpload(...) end
 local ok,err=pcall(function()
  local journal=J2Host()
  local model=Refresh()
  local asg=type(model)=='table' and type(model.assignment)=='table' and model.assignment or {}
  local free
  for _,c in ipairs(A.GetWishlistCandidates() or {}) do if tonumber(c.slot)==107 then free=c end end
  local fixture=C.setup(asg.state=='unassigned' and J2Stored(2)==nil,
   'J2: fixture: Saved Build 2 (Fire PvE) is active and holds no assignment',tostring(asg.state))
  fixture=C.setup(free~=nil and free.name=='W-Free' and free.lockEvidenceStatus~='unavailable',
   'J2: fixture: the existing valid Wishlist W-Free is listed',free and free.name) and fixture
  fixture=C.setup(not Auto() and not journal:IsShown(),'J2: fixture: Auto is OFF and the Echo Journal is closed') and fixture
  if not fixture then return end
  local base=J2Frontier(J)
  -- 1. The live checklist, through the ... menu.
  local f=J2OpenViaMenu('J2')
  if not f then return end
  local rows=Rows(f)
  print('OBSERVED','J2 unassigned rows='..table.concat(rows,' / '))
  C.expect(Has(rows[2],'[done] Destination') and Has(rows[2],J2_FIRE),'J2: the checklist names the existing Saved Build as the destination',rows[2])
  C.expect(Has(rows[3],'[to do] Wishlist') and Has(rows[3],'None assigned') and not Has(rows[3],'Echoes first')
   and not Has(rows[3],'unavailable'),'J2: its Wishlist step is to do: unassigned, not empty or unavailable',rows[3])
  C.expect(f.steps~=nil and f.steps.complete==false,'J2: setup is not complete while unassigned')
  C.guard(J2Unchanged(J2Frontier(J),base,true),'J2 frontier 1: opening the checklist changes nothing',J2Describe(J2Frontier(J)))
  -- 2. Its Assign Wishlist... route to the real chooser, then cancel.
  C.expect(f.assign~=nil and V.Plain(f.assign:GetText() or '')=='Assign Wishlist...','J2: the checklist offers Assign Wishlist...')
  if not f.assign then return end
  f.assign:Click()
  local shown,title=J2Chooser()
  print('OBSERVED','J2 chooser shown='..tostring(shown)..' title='..title)
  C.expect(shown and not f:IsShown() and journal:IsShown() and title=='Assign to: Fire PvE',
   'J2: Assign Wishlist... opens the Echo Journal chooser titled with the captured Saved Build',title)
  if not shown then return end
  C.guard(J2Unchanged(J2Frontier(J),base,true),'J2 frontier 1: opening the chooser assigns, uploads, acts and sends nothing',
   J2Describe(J2Frontier(J)))
  J2CloseChooser()
  C.guard(not (J2Chooser()) and J2Unchanged(J2Frontier(J),base,true),
   'J2 frontier 1: cancelling the chooser assigns, uploads, acts and sends nothing',J2Describe(J2Frontier(J)))
  f=Open('J2 after cancel')
  if not f then return end
  rows=Rows(f)
  C.expect(Has(rows[3],'[to do] Wishlist') and f.steps~=nil and f.steps.complete==false,
   'J2: after cancel the Wishlist step is still to do; nothing claims completion',rows[3])
  C.guard(J2Stored(2)==nil and J2Unchanged(J2Frontier(J),base,true),
   'J2 frontier 1: the whole passive navigation left Saved Build 2 unassigned',J2Describe(J2Frontier(J)))
  -- 3. The deliberate choice of the existing Wishlist (Auto OFF: one click).
  journal:Hide()
  f.assign:Click()
  shown,title=J2Chooser()
  C.expect(shown and title=='Assign to: Fire PvE','J2: the chooser opens again for the same captured Saved Build',title)
  if not shown then return end
  local row=J2Row('W-Free')
  C.setup(row~=nil,'J2: fixture: the chooser lists W-Free')
  if not row then return end
  local before=J2Frontier(J)
  local said=J2Heard(function() row.nameButton:Click() end)
  local after=J2Frontier(J)
  print('OBSERVED','J2 assign said='..said..' '..J2Describe(after))
  C.guard(after.writes==before.writes+1 and after.slots=='2:1',
   'J2 frontier 2: the explicit choice makes exactly one association write, for Saved Build 2',J2Describe(after))
  C.guard(after.uploads==before.uploads and after.uploadCalls==before.uploadCalls and after.others==before.others
   and after.sent==before.sent and after.auto==before.auto and after.orb==before.orb,
   'J2 frontier 2: assigning the existing Wishlist uploads, acts, sends and spends nothing; Auto unchanged',J2Describe(after))
  C.guard(said:find("'W-Free' is now the Wishlist for Saved Build 'Fire PvE'",1,true)~=nil,
   'J2: the choice is confirmed visibly, naming the Wishlist and the Saved Build',said)
  -- 4. Production readback, then later passive refreshes.
  local _,settled=J2Settle(function(m)
   local a=type(m)=='table' and type(m.assignment)=='table' and m.assignment or {}
   return a.state=='ready' and a.name=='W-Free'
  end)
  local read=A.AssignedWishlist() or {}
  local stored=J2Stored(2)
  local readOk=C.guard(settled and read.state=='ready' and read.name=='W-Free' and tonumber(read.activeSlot)==2
   and type(stored)=='table' and stored.name=='W-Free' and J2Stored(1)==nil and J2Stored(3)==nil,
   'J2: production readback: Saved Build 2 holds W-Free and no other destination changed',tostring(read.state)..'/'..tostring(read.name))
  if readOk then
   f=Open('J2 readback')
   if not f then return end
   rows=Rows(f)
   print('OBSERVED','J2 readback rows='..table.concat(rows,' / ')..' summary='..V.Plain(f.summary:GetText() or ''))
   if readbackOracle then
    C.expect(J2Readback(rows,J2_FIRE,'W-Free'),'J2: the checklist reads back the captured destination and its assigned Wishlist',
     table.concat(rows,' / '))
   end
   C.expect(f.steps~=nil and f.steps.complete==true and Has(f.summary:GetText(),'3 of 3'),'J2: every setup step is done now',
    f.summary:GetText())
   local facts=type(Nexus.Panel.SetupFacts)=='function' and Nexus.Panel.SetupFacts() or {}
   local d=type(facts.destination)=='table' and facts.destination or {}
   C.expect(d.kind=='savedBuild' and d.slot==2 and d.active==true and d.wishlist=='W-Free' and d.wishlistState=='assigned',
    'J2: the status facts name the same destination and Wishlist',
    tostring(d.kind)..'/'..tostring(d.slot)..'/'..tostring(d.wishlist)..'/'..tostring(d.wishlistState))
   C.expect(Has(Status(f)[1],'Auto: OFF'),'J2: the status still says Auto OFF',Status(f)[1])
   if Nexus.JournalTab and Nexus.JournalTab.RefreshAssociations then Nexus.JournalTab.RefreshAssociations() end
   local selector=_G.NexusActiveWishlistSelector
   local readback=selector and selector.text and V.Plain(selector.text:GetText() or '') or ''
   C.guard(Has(readback,'W-Free'),'J2: the Echo Journal selector reads W-Free back',readback)
  else
   print('OBSERVED','J2: not evaluated after the failed production readback GUARD: the checklist, status and selector readbacks, the readback after refreshes, and Saved Build 2 keeping W-Free')
  end
  local settledFrontier=J2Frontier(J)
  Refresh();Refresh()
  Nexus.QuickStart.RefreshChecklist();H.Advance(1)
  f=Open('J2 passive refresh')
  local now=J2Frontier(J)
  C.guard(J2Unchanged(now,settledFrontier,false),
   'J2 frontier 3: later passive checklist and status refreshes write, upload, act and turn nothing ON',J2Describe(now))
  if readOk and readbackOracle then
   C.expect(f~=nil and J2Readback(Rows(f),J2_FIRE,'W-Free'),'J2: the readback stays the same across refreshes')
  end
  if not f then return end
  -- 5. One destination change while the chooser is open: the game shows Saved
  -- Build 1 (One) as active. No chooser callback is delivered here: W-Free is
  -- now Saved Build 2's own Wishlist and the chooser lists only the other
  -- Wishlists, so it offers no unassigned W-Free row, and an absent W-Free row
  -- says nothing about whether the chooser closed. The delayed callback of a
  -- visible, unassigned row is measured in J2b.
  J2CloseChooser();journal:Hide()
  f.assign:Click()
  shown,title=J2Chooser()
  C.expect(shown and title=='Assign to: Fire PvE','J2 stale: the chooser opens for the captured Saved Build 2',title)
  if not shown then return end
  local changeBase=J2Frontier(J)
  H.perks.serverActiveSlot=1;H.Notify();A.Poll()
  local slots=A.Slots()
  local activeOk=C.setup(type(slots)=='table' and slots.activeSlot==1,'J2 stale: fixture: Saved Build 1 (One) is active while the chooser is open',
   type(slots)=='table' and slots.activeSlot or nil)
  local stillShown,nowTitle=J2Chooser()
  local freeRow=stillShown and J2Row('W-Free') or nil
  local picker=_G.NexusWishlistOnlyPicker
  local empty=picker and picker.emptyRow and picker.emptyRow:IsShown() and V.Plain(picker.emptyRow:GetText() or '') or ''
  local held=J2Stored(2)
  print('OBSERVED','J2 stale chooser (measured): shown='..tostring(stillShown)..' title='..nowTitle
   ..' W-Free row listed='..tostring(freeRow~=nil)..' empty row='..empty..' Saved Build 2 holds='
   ..tostring(type(held)=='table' and held.name or nil)..'; no chooser callback is delivered in J2 (see J2b)')
  if not activeOk then
   print('OBSERVED','J2 stale: not evaluated after the failed SETUP (Saved Build 1 is not active): the runtime destination GUARD and the stale checklist readback')
  end
  local changed2=J2Frontier(J)
  C.guard(changed2.writes==changeBase.writes and changed2.uploads==changeBase.uploads and changed2.uploadCalls==changeBase.uploadCalls
   and changed2.others==changeBase.others and changed2.auto==changeBase.auto and changed2.orb==changeBase.orb,
   'J2 stale: the context change assigns, uploads, acts and spends nothing; Auto unchanged',J2Describe(changed2))
  if activeOk then
   local _,moved=J2Settle(function(m)
    return type(m)=='table' and type(m.progress)=='table' and tonumber(m.progress.activeSlot)==1
   end)
   local movedOk=C.guard(moved,'J2 stale: the runtime reads Saved Build 1 as the destination it acts on now')
   if movedOk then
    f=Open('J2 stale readback')
    if not f then return end
    rows=Rows(f)
    local one=J2Stored(1)
    print('OBSERVED','J2 stale rows='..table.concat(rows,' / ')..' slot1='..tostring(type(one)=='table' and one.name or nil))
    if truthfulOracle then
     C.expect(J2Truthful(rows,J2_ONE,one) and not Has(rows[2],'Fire PvE'),
      'J2 stale: the checklist names the destination it acts on now; its Wishlist is done only if that destination holds one',
      table.concat(rows,' / '))
    end
    C.expect(f.steps~=nil and f.steps.complete==(type(one)=='table'),
     'J2 stale: setup is complete only when the current destination is assigned',tostring(f.steps and f.steps.complete))
   end
  end
  if readOk then
   local kept=J2Stored(2)
   C.guard(type(kept)=='table' and kept.name=='W-Free','J2 stale: Saved Build 2 keeps W-Free')
  end
 end)
 A.SetLoadoutWishlist,A.UploadWishlist=counted,realUpload
 if not ok then error(err,0) end
end)

-- J2b/J2c (issue #131 J2 review fix): the delayed chooser callback. J2's
-- stale phase cannot exercise it: by then W-Free is Saved Build 2's own
-- Wishlist and the chooser lists only the other Wishlists. A fresh boot keeps
-- Saved Build 2 unassigned, so W-Free is a visible, unassigned row of the
-- chooser that the checklist's Assign Wishlist... opens. Before the
-- destination change, that row, the production OnClick function installed on
-- it and the Saved Build the chooser title names are captured. After the
-- harness has established Saved Build 1 (One) as the destination Nexus acts
-- on, exactly that captured function is delivered once. This is a SYNTHETIC
-- queued-callback boundary: the function is called directly, not clicked; no
-- native timing, frame visibility or visible-click claim is made, and no
-- current row is looked up again or rebound for the delivery.
-- Expected under the current contract (ui/JournalTab.lua
-- AssociateWishlistOnly and AssignWithConsent, Auto OFF; core/GameAdapter.lua
-- SetLoadoutWishlist): the callback assigns at once to the Saved Build its
-- chooser captured, which still holds Echoes: exactly one SetLoadoutWishlist
-- call, for Saved Build 2, no other assignment or role writer, and Saved
-- Build 1, the destination now, stays unassigned. This records the
-- captured-target contract and adds no "assign the current destination"
-- policy. Categories: GUARD for the chooser callback (current behaviour, not
-- added by the checklist; not executed by the author on M6), EXPECT for the
-- M7 checklist readback, SETUP for the fixture and the J2c discriminators.
local J2B_WRITERS={'ConfirmWishlistRoles'}
for _,k in ipairs(WRITERS) do J2B_WRITERS[#J2B_WRITERS+1]=k end
local J2B_DEST={SetFirstRunWishlist='first-run',SetFirstLoadoutWishlistIdentity='first-run',
 ClearFirstRunWishlist='first-run',SetFirstRunWishlistIdentity='first-run',ConfirmWishlistRoles='roles'}
-- Pass-through spies over every assignment and role writer (with the
-- destination each call names) and the adapter upload. J.route is J2c's
-- test-only fault router; it is nil everywhere else. Returns the function
-- that restores every replaced adapter field.
local function J2bSpy(log,J)
 local adapter,saved=A,{}
 for _,k in ipairs(J2B_WRITERS) do
  local real=adapter[k]
  if type(real)=='function' then
   saved[k]=real
   adapter[k]=function(...)
    local first=...
    log[#log+1]={fn=k,dest=J2B_DEST[k] or tostring(tonumber(first) or first)}
    local route=J.route and J.route[k]
    if route then return route(real,...) end
    return real(...)
   end
  end
 end
 local upload=adapter.UploadWishlist
 if type(upload)=='function' then
  saved.UploadWishlist=upload
  adapter.UploadWishlist=function(...) J.uploadCalls=J.uploadCalls+1;return upload(...) end
 end
 return function() for k,real in pairs(saved) do adapter[k]=real end end
end
-- Every stored assignment by destination ('first' is the first-run plan).
local function J2bLinks()
 local s=Nexus.Store.State() or {}
 local out={}
 for k,r in pairs(type(s.loadoutWishlists)=='table' and s.loadoutWishlists or {}) do
  out[tostring(k)]=type(r)=='table' and tostring(r.name) or tostring(r)
 end
 out.first=type(s.firstRunWishlist)=='table' and tostring(s.firstRunWishlist.name) or tostring(s.firstRunWishlist)
 return out
end
local function J2bChanged(before,after)
 local keys,seen={},{}
 for _,t in ipairs({before,after}) do
  for k in pairs(t) do if not seen[k] then seen[k]=true;keys[#keys+1]=k end end
 end
 table.sort(keys)
 local out={}
 for _,k in ipairs(keys) do
  if before[k]~=after[k] then out[#out+1]=k..':'..tostring(before[k])..'>'..tostring(after[k]) end
 end
 return out
end
-- The measured facts after the boundary: the writer calls and the readback
-- changes since the capture.
local function J2bFacts(ctx,log,delivered,raised)
 local calls={}
 for i=ctx.calls+1,#log do calls[#calls+1]=log[i] end
 return {delivered=delivered,raised=raised,calls=calls,named=ctx.named,changed=J2bChanged(ctx.links,J2bLinks())}
end
local function J2bCalls(o)
 local out={}
 for _,c in ipairs(o.calls) do out[#out+1]=c.fn..'('..c.dest..')' end
 return table.concat(out,',')
end
-- The J2b oracle: the captured callback was delivered and did not raise,
-- exactly one writer call was made, SetLoadoutWishlist naming the Saved Build
-- the chooser title named, and the readback changed exactly that Saved Build,
-- to W-Free. Returns the verdict and every reason it fails.
local function J2bVerdict(o)
 local why={}
 if not o.delivered then why[#why+1]='the captured callback was not delivered' end
 if o.raised then why[#why+1]='the callback raised: '..o.raised end
 if #o.calls~=1 then why[#why+1]=#o.calls..' writer calls ['..J2bCalls(o)..']' end
 local c=o.calls[1]
 if c and not (c.fn=='SetLoadoutWishlist' and c.dest==tostring(o.named)) then
  why[#why+1]='writer '..c.fn..' named '..c.dest..', not Saved Build '..tostring(o.named)
 end
 local want=tostring(o.named)..':nil>W-Free'
 if not (#o.changed==1 and o.changed[1]==want) then
  why[#why+1]='readback changed ['..table.concat(o.changed,',')..'], not ['..want..']'
 end
 return #why==0,#why==0 and 'accepted' or table.concat(why,'; ')
end
-- A fresh boot up to the boundary: the chooser for Saved Build 2 opened from
-- the checklist, the visible unassigned W-Free row and its production OnClick
-- captured, then Saved Build 1 established as the destination. Nil after a
-- failed SETUP: a missing prerequisite is a failed SETUP, never a pass.
local function J2bReach(tag,J,log)
 local journal=J2Host()
 local model=Refresh()
 local asg=type(model)=='table' and type(model.assignment)=='table' and model.assignment or {}
 if not C.setup(asg.state=='unassigned' and J2Stored(2)==nil and not Auto() and not journal:IsShown() and #log==0,
  tag..': fixture: Saved Build 2 (Fire PvE) is active and unassigned, Auto is OFF, the Echo Journal is closed and nothing is written',
  tostring(asg.state)..' writers='..#log) then return nil end
 local f=Open(tag)
 if not f then return nil end
 if not C.setup(f.assign~=nil,tag..': fixture: the checklist offers Assign Wishlist...') then return nil end
 f.assign:Click()
 local shown,title=J2Chooser()
 local row=shown and J2Row('W-Free') or nil
 local button=row and row.nameButton or nil
 local handler=button and button:GetScript('OnClick') or nil
 local named=J2_TITLE_SLOT[title]
 local pre=A.Slots()
 print('OBSERVED',tag..' before the destination change (measured): chooser shown='..tostring(shown)..' title='..title
  ..' (names slot '..tostring(named)..') W-Free row visible='..tostring(row~=nil)..' production OnClick='..type(handler)
  ..' native active slot='..tostring(type(pre)=='table' and pre.activeSlot or nil)..' writers='..#log)
 if not C.setup(shown and named==2 and row~=nil and type(handler)=='function' and type(pre)=='table' and pre.activeSlot==2 and #log==0,
  tag..': fixture: before the destination change the chooser for Saved Build 2 shows a visible, unassigned W-Free row with its production OnClick',
  title) then return nil end
 local ctx={button=button,handler=handler,title=title,named=named,base=J2Frontier(J),links=J2bLinks(),calls=#log}
 H.perks.serverActiveSlot=1;H.Notify();A.Poll()
 local _,moved=J2Settle(function(m)
  return type(m)=='table' and type(m.progress)=='table' and tonumber(m.progress.activeSlot)==1
 end)
 local slots=A.Slots()
 local selected=type(A.SelectedSavedBuild)=='function' and A.SelectedSavedBuild(slots) or nil
 if not C.setup(moved and type(slots)=='table' and slots.activeSlot==1 and selected==1,
  tag..': fixture: the harness established Saved Build 1 (One) as the destination Nexus acts on',
  tostring(type(slots)=='table' and slots.activeSlot or nil)..'/'..tostring(selected)) then return nil end
 return ctx
end
-- The synthetic queued-callback delivery: the captured function, called once.
local function J2bDeliver(ctx)
 local delivered,raised=false,nil
 local said=J2Heard(function()
  delivered=true
  local called,why=pcall(ctx.handler,ctx.button,'LeftButton')
  if not called then raised=tostring(why) end
 end)
 return delivered,raised,said
end

C.scenario('J2b a delayed chooser callback, captured before the destination change, assigns only the Saved Build its chooser captured',function()
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusLoadoutAssociationPanel=nil
 Boot(2)
 local log,J={},{slotWrites={},uploadCalls=0}
 local restore=J2bSpy(log,J)
 local ok,err=pcall(function()
  local ctx=J2bReach('J2b',J,log)
  if not ctx then return end
  local stillShown,nowTitle=J2Chooser()
  print('OBSERVED','J2b after the destination change, before delivery (measured): chooser shown='..tostring(stillShown)
   ..' title='..nowTitle..' captured row visible='..tostring(ctx.button:IsVisible())
   ..' its OnClick replaced since capture='..tostring(ctx.button:GetScript('OnClick')~=ctx.handler))
  local delivered,raised,said=J2bDeliver(ctx)
  local _,settled=J2Settle(function(m)
   local a=type(m)=='table' and type(m.assignment)=='table' and m.assignment or {}
   return type(m)=='table' and type(m.progress)=='table' and tonumber(m.progress.activeSlot)==1 and a.state=='unassigned'
  end)
  local o=J2bFacts(ctx,log,delivered,raised)
  local after=J2Frontier(J)
  print('OBSERVED','J2b synthetic queued-callback delivery (the captured production OnClick called directly once; no native click, timing or visibility claim): delivered='
   ..tostring(delivered)..' raised='..tostring(raised)..' writers=['..J2bCalls(o)..'] readback changed=['
   ..table.concat(o.changed,',')..'] said='..said)
  local accepted,why=J2bVerdict(o)
  C.guard(accepted,'J2b: the delivered callback makes exactly one association write, SetLoadoutWishlist for Saved Build 2 (the Saved Build its chooser title named), and the readback shows only Saved Build 2 changed, to W-Free',why)
  C.guard(Has(said,"'W-Free' is now the Wishlist for Saved Build 'Fire PvE'"),
   'J2b: its visible confirmation names the captured Saved Build, not the destination now',said)
  C.guard(after.uploads==ctx.base.uploads and after.uploadCalls==ctx.base.uploadCalls and after.others==ctx.base.others
   and after.auto==ctx.base.auto and after.orb==ctx.base.orb and after.seen==ctx.base.seen,
   'J2b: the delayed callback uploads, acts and spends nothing; Auto and the Welcome are unchanged',J2Describe(after))
  local read=A.AssignedWishlist() or {}
  local captured=A.GetLoadoutWishlist(2)
  C.guard(settled and tonumber(read.activeSlot)==1 and read.state=='unassigned' and type(captured)=='table' and captured.name=='W-Free',
   'J2b: production readback: the destination Nexus acts on now (Saved Build 1) stays unassigned, and the captured Saved Build 2 reads W-Free',
   tostring(read.activeSlot)..'/'..tostring(read.state)..'/'..tostring(type(captured)=='table' and captured.name or nil))
  local f=Open('J2b current readback')
  if not f then return end
  local rows=Rows(f)
  print('OBSERVED','J2b current checklist rows='..table.concat(rows,' / '))
  C.expect(J2Truthful(rows,J2_ONE,nil) and not Has(rows[2],'Fire PvE'),
   'J2b: the checklist names the destination Nexus acts on now (Saved Build 1, unassigned), not the Saved Build the chooser title captured',
   table.concat(rows,' / '))
 end)
 restore()
 if not ok then error(err,0) end
end)

C.scenario('J2c fixture discriminators (not product evidence): the J2b oracle rejects a skipped delivery and a write routed to another Saved Build',function()
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusLoadoutAssociationPanel=nil
 Boot(2)
 local log,J={},{slotWrites={},uploadCalls=0}
 local restore=J2bSpy(log,J)
 local ok,err=pcall(function()
  local ctx=J2bReach('J2c',J,log)
  if not ctx then return end
  -- Control 1: the captured callback is not delivered.
  Refresh()
  local skipped=J2bFacts(ctx,log,false,nil)
  local acceptedSkip,whySkip=J2bVerdict(skipped)
  print('OBSERVED','J2c control 1, delivery skipped (measured): writers=['..J2bCalls(skipped)..'] readback changed=['
   ..table.concat(skipped.changed,',')..'] oracle: '..whySkip)
  C.setup(not acceptedSkip and #skipped.calls==0 and #skipped.changed==0,
   'J2c: fixture discriminator: with the captured callback not delivered there is no writer call and no readback change, and the J2b oracle rejects the outcome',whySkip)
  -- Control 2: an isolated test-only router below the writer log sends the
  -- delivered callback's SetLoadoutWishlist to Saved Build 1 instead.
  J.route={SetLoadoutWishlist=function(real,_,...) return real(1,...) end}
  local delivered,raised=J2bDeliver(ctx)
  J.route=nil
  Refresh()
  local routed=J2bFacts(ctx,log,delivered,raised)
  local acceptedRoute,whyRoute=J2bVerdict(routed)
  local one,two=J2Stored(1),J2Stored(2)
  print('OBSERVED','J2c control 2, write routed to Saved Build 1 (measured): writers=['..J2bCalls(routed)..'] readback changed=['
   ..table.concat(routed.changed,',')..'] oracle: '..whyRoute)
  C.setup(delivered and not raised and not acceptedRoute and #routed.calls==1 and routed.calls[1].dest=='2'
   and type(one)=='table' and one.name=='W-Free' and two==nil,
   'J2c: fixture discriminator: when the delivered callback\'s write is routed to Saved Build 1, the writer call still names Saved Build 2, the readback shows Saved Build 1 changed, and the J2b oracle rejects the outcome',whyRoute)
 end)
 J.route=nil
 restore()
 if not ok then error(err,0) end
end)

C.finish('(read-only checklist from current facts; Welcome and warning are not facts; navigation only)')
