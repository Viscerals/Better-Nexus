-- M2 (UX-17 quick work, UX-06): Help opens any page directly and leads with
-- a primary setup path (Setup / Welcome, Assign Wishlist..., Wishlist
-- Editor); it works during loading, where the routes that need start-up say
-- so instead of opening; and every "assign" route opens the Echo Journal
-- with its existing Wishlist chooser already open and titled with the target
-- it assigns to. Opening, closing or refusing a route assigns, uploads,
-- activates, spends and sends nothing; only a chooser row click assigns,
-- through the existing writer and its empty-Saved-Build refusal. A missing
-- Character Progression button is said before any Nexus window is closed.
-- The panel's route is the present JournalTab helper, asked for its chooser
-- (H5, M2-route-repair).
-- EXPECT: behaviour added in M2 (fails on the accepted M1 cut). GUARD:
-- existing Help/Journal behaviour that must keep holding. SETUP: fixture.
-- Real TOC load/boot, real Help, Panel, QuickStart and Journal controls;
-- synthetic host services, saved data and Journal frames only.
local V=dofile('tests/prototype/view_regression_support.lua')
local C=V.Checker('ux_help_navigation')
local H,A,writes
local WRITERS={'SetLoadoutWishlist','SetFirstRunWishlist','SetLoadoutWishlistIdentity',
 'SetFirstLoadoutWishlistIdentity','UpdateWishlistAssociationAfterSave','ClearLoadoutWishlist','ClearFirstRunWishlist'}
local E1={{spellId=201172,quality=0,stacks=1}}

local function Reset()
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 NexusHelpWindow=nil;NexusQuickStart=nil;NexusPanel=nil;NexusEditorFrame=nil
 ProjectEbonholdEchoJournal=nil;EchoJournalMicroButton=nil
 NexusActiveWishlistSelector=nil;NexusWishlistOnlyPicker=nil;NexusLoadoutAssociationPanel=nil
end
local function Spy()
 writes={}
 for _,k in ipairs(WRITERS) do
  local real=A[k]
  if type(real)=='function' then writes[k]=0;A[k]=function(...) writes[k]=writes[k]+1;return real(...) end end
 end
end
local function Writes() local n=0;for _,c in pairs(writes or {}) do n=n+c end;return n end
local function Boot(slots,active)
 Reset()
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=80
 H.AddEcho(201172,'Echo One',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots=slots
 H.perks.serverActiveSlot=active
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
 Spy()
end
local function HelpButton(text)
 local f=NexusHelpWindow
 for _,x in ipairs(H.frames) do if f and x:GetParent()==f and x.kind=='Button' and x:GetText()==text then return x end end
end
local function Note() return NexusHelpWindow and NexusHelpWindow.note and V.Plain(NexusHelpWindow.note:GetText() or '') or '' end
local function Auto() return Nexus.RecomputeStats and Nexus.RecomputeStats().autoEnabled==true or false end
local function JournalHost()
 local journal=_G.ProjectEbonholdEchoJournal or CreateFrame('Frame','ProjectEbonholdEchoJournal',UIParent)
 journal:Hide()
 local micro=_G.EchoJournalMicroButton or CreateFrame('Button','EchoJournalMicroButton',UIParent)
 micro:SetScript('OnClick',function() journal:Show() end)
 return journal
end
local function Chooser()
 local p=_G.NexusWishlistOnlyPicker
 return p~=nil and p:IsShown(),p and p.title and V.Plain(p.title:GetText() or '') or ''
end
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...));realPrint(...) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return table.concat(heard,' / ')
end
local function PanelButton(text)
 for _,f in ipairs(H.frames) do if f.kind=='Button' and f:GetParent()==NexusPanel and f:GetText()==text then return f end end
end

C.scenario('H1 Help during loading: direct pages; setup routes say why they wait',function()
 Reset()
 H=dofile('tests/prototype/harness.lua')
 local T=dofile('tests/prototype/startup_support.lua');T.Load()
 local actions,sent=#H.actions,#H.sent
 -- The reference pages (/nexus help opens the guided setup coach).
 SlashCmdList.NEXUS('reference')
 local f=NexusHelpWindow
 C.setup(f and f:IsShown(),'H1: fixture: Help opens before start-up')
 C.setup(type(Nexus.StartupStatus)~='function' or not Nexus.StartupStatus().coreReady,'H1: fixture: start-up is not ready')
 local labels={'Start','Wishlists','Auto','Sharing','Orbs','Problems','About'}
 local found=0
 for _,label in ipairs(labels) do if HelpButton(label) then found=found+1 end end
 C.expect(found==7,'H1: Help offers one direct button per page',found)
 local orbs=HelpButton('Orbs')
 if orbs then
  orbs:Click()
  C.expect(f.title:GetText():find('Orbs / Lost Memories',1,true)~=nil and f.page:GetText()=='Page 5 / 8'
   and not orbs:IsEnabled(),'H1: a page button opens its page directly and shows it as current',f.title:GetText())
  HelpButton('Start'):Click()
  C.expect(f.page:GetText()=='Page 1 / 8' and f.body:GetText():find('Start here',1,true)==1,
   'H1: the Start page leads with the setup path',f.body:GetText():sub(1,60))
 end
 local assign,editor,setup=HelpButton('Assign Wishlist...'),HelpButton('Wishlist Editor'),HelpButton('Setup / Welcome')
 C.expect(assign~=nil and editor~=nil and setup~=nil,'H1: the setup row offers Setup / Welcome, Assign Wishlist... and Wishlist Editor')
 if assign then
  local said=Heard(function() assign:Click() end)
  C.expect(f:IsShown() and Note():find('after start-up finishes',1,true)~=nil and said:find('Nothing was opened or assigned',1,true)~=nil,
   'H1: Assign Wishlist waits for start-up and says so in Help',Note())
 end
 if editor then
  editor:Click()
  C.expect(f:IsShown() and Note():find('after start-up finishes',1,true)~=nil
   and not (NexusEditorFrame and NexusEditorFrame:IsShown()),'H1: the Wishlist Editor waits for start-up and says so',Note())
 end
 C.guard(#H.actions==actions and #H.sent==sent,'H1: Help and its routes during loading act and send nothing')
 HelpButton('Next'):Click()
 C.guard(f.page:GetText()=='Page 2 / 8' and (not HelpButton('Wishlists') or not HelpButton('Wishlists'):IsEnabled()),
  'H1: Next still navigates, and the page buttons follow it',f.page:GetText())
end)

C.scenario('H2 Help Assign Wishlist... opens the Journal chooser for the target; nothing is assigned',function()
 Boot({[1]={name='One',verified=true,echoes=E1},[107]={name='W-Free',verified=false,echoes=E1}},1)
 local journal=JournalHost()
 Nexus.Help.Show('rolling')
 Nexus.WishlistEditor.Show()
 C.setup(NexusEditorFrame and NexusEditorFrame:IsShown(),'H2: fixture: the Wishlist editor is open too')
 local actions,sent,auto=#H.actions,#H.sent,Auto()
 local assign=HelpButton('Assign Wishlist...')
 C.expect(assign~=nil,'H2: Help offers Assign Wishlist...')
 if not assign then return end
 assign:Click()
 local shown,title=Chooser()
 print('OBSERVED','H2 chooser',tostring(shown),title)
 C.expect(not NexusHelpWindow:IsShown() and not NexusEditorFrame:IsShown() and journal:IsShown(),
  'H2: Help and the editor close; the Echo Journal opens')
 C.expect(shown and title=='Assign to: One','H2: the chooser is open and titled with the Saved Build it assigns to',title)
 C.guard(Writes()==0 and #H.actions==actions and #H.sent==sent and Auto()==auto,'H2: opening the route assigns, acts and sends nothing')
 if shown then
  NexusActiveWishlistSelector:Click()
  C.guard(not Chooser() and Writes()==0,'H2: closing the chooser assigns nothing')
 end
end)

C.scenario('H3 no Character Progression button: said first; nothing is closed',function()
 Boot({[1]={name='One',verified=true,echoes=E1}},1)
 Nexus.Help.Show('start')
 local assign=HelpButton('Assign Wishlist...')
 C.setup(_G.EchoJournalMicroButton==nil,'H3: fixture: the game button is absent')
 if assign then
  local said=Heard(function() assign:Click() end)
  C.expect(NexusHelpWindow:IsShown() and Note():find('Character Progression button was not found',1,true)~=nil,
   'H3: Help stays open and says the route cannot open',Note()..' | '..said)
 else
  C.expect(false,'H3: Help offers Assign Wishlist...')
 end
 -- The main panel's Assign Wishlist keeps the open editor when the route cannot open.
 Nexus.Panel.Show()
 Nexus.WishlistEditor.Show()
 local button=PanelButton('Assign Wishlist')
 C.setup(button~=nil and NexusEditorFrame:IsShown(),'H3: fixture: the panel offers Assign Wishlist while the editor is open')
 if not button then return end
 local said=Heard(function() button:Click() end)
 C.expect(NexusEditorFrame:IsShown() and said:find('nothing was opened or assigned',1,true)~=nil,
  'H3: without the game button the panel closes no window and says why',said)
 C.guard(Writes()==0 and #H.actions==0,'H3: nothing is assigned or performed')
end)

C.scenario('H4 the panel and Welcome routes open the chooser; the empty Saved Build title',function()
 Boot({[1]={name='One',verified=true,echoes=E1},[107]={name='W-Free',verified=false,echoes=E1}},1)
 local journal=JournalHost()
 Nexus.Panel.Show()
 local button=PanelButton('Assign Wishlist')
 C.setup(button~=nil,'H4: fixture: the panel shows the setup Assign Wishlist button')
 if not button then return end
 local actions,sent=#H.actions,#H.sent
 button:Click()
 local shown,title=Chooser()
 C.guard(journal:IsShown(),'H4: Assign Wishlist opens the Echo Journal')
 C.expect(shown and title=='Assign to: One','H4: the panel route opens the chooser titled with its target',title)
 C.guard(Writes()==0 and #H.actions==actions and #H.sent==sent,'H4: and assigns, acts and sends nothing')
 -- The informational Welcome's "Set up current build": the same route. (The
 -- chooser is closed first; the synthetic Journal does not hide children.)
 if Chooser() then NexusActiveWishlistSelector:Click() end
 journal:Hide()
 local quick=Nexus.QuickStart
 local opened=quick and quick.ShowSetup and quick.ShowSetup()
 local seen=rawget(NexusDB,'hasSeenQuickStart')
 if opened then
  for _,c in ipairs(NexusQuickStart.children) do if c.kind=='Button' and c:GetText()=='Set up current build' then c:Click() end end
  shown,title=Chooser()
  C.expect(journal:IsShown() and shown and title=='Assign to: One' and rawget(NexusDB,'hasSeenQuickStart')==seen,
   'H4: Set up current build opens the chooser; the replay records nothing',title)
 else
  C.expect(false,'H4: the informational Welcome opens for Set up current build')
 end
 -- An empty selected Saved Build: the chooser says assigning is refused, and a pick is refused.
 local rows=H.Clone(H.perks.serverBuildSlots);rows[2]={name='Empty two',verified=true,echoes={}}
 H.perks.serverBuildSlots=rows;H.perks.serverActiveSlot=2;H.Notify();A.Poll();H.Advance(1)
 if Chooser() then NexusActiveWishlistSelector:Click() end
 journal:Hide()
 button=PanelButton('Assign Wishlist')
 if button then button:Click() end
 shown,title=Chooser()
 C.expect(shown and title=='Empty Saved Build: assigning is refused','H4: an empty Saved Build\'s chooser says assigning is refused',title)
 local row
 for _,r in ipairs(NexusWishlistOnlyPicker and NexusWishlistOnlyPicker.children or {}) do
  if r.nameButton and r:IsVisible() then row=r end
 end
 if row then
  local said=Heard(function() row.nameButton:Click() end)
  C.guard(writes.SetLoadoutWishlist==1 and (A.GetLoadoutWishlist(2)==nil),
   'H4: a pick for the empty Saved Build is refused by the existing writer',said)
 end
 C.guard(#H.actions==actions,'H4: no game action from any route')
end)

-- The panel's Assign Wishlist route is the present JournalTab helper (the
-- older batch_journal_fallback_argument pins the delegation and the native
-- no-tab fallback): a substituted helper is used once, with the chooser
-- requested, and the native Journal Show is not called. No separate probe
-- overrides the helper; the real helper checks the game button itself (H3).
C.scenario('H5 the panel route is the present helper, with its chooser',function()
 Boot({[1]={name='One',verified=true,echoes=E1}},1)
 Nexus.Panel.Show()
 local button=PanelButton('Assign Wishlist')
 local journal,native=Nexus.JournalTab,ProjectEbonhold.EchoJournal
 local helper=journal and journal.OpenBuilds
 C.setup(button~=nil and button:IsEnabled() and type(helper)=='function' and type(native)=='table'
  and _G.EchoJournalMicroButton==nil,'H5: fixture: the setup button and the real helper; the game button is absent')
 if not (button and type(helper)=='function' and type(native)=='table') then return end
 local calls,chooser,shows=0,nil,0
 local realShow=native.Show
 local actions,sent=#H.actions,#H.sent
 journal.OpenBuilds=function(...) calls=calls+1;chooser=(...) end
 native.Show=function() shows=shows+1 end
 local ok,said=pcall(Heard,function() button:Click() end)
 journal.OpenBuilds,native.Show=helper,realShow
 assert(ok,said)
 C.expect(calls==1 and chooser==true and shows==0,
  'H5: the present helper is used once, with the chooser, and the native Show is not called',
  calls..' call(s), chooser='..tostring(chooser)..', native Show '..shows..' | '..said)
 C.guard(Writes()==0 and #H.actions==actions and #H.sent==sent,'H5: nothing is assigned, performed or sent')
end)

C.finish('(direct Help pages and setup path; assign routes open the existing chooser; nothing assigned by navigation)')
