-- M4 (UX-14 / LP-14, UX-15 / LP-15): DPS records and leaderboards say what
-- they are: the best record this client knows (shared), in its real
-- category, with only the facts the record carries (fight duration, level,
-- recorded date) and its own owner flag; unknown stays unsaid, never "Level 0".
-- Build Library cards name the category of their best-DPS headline and say
-- when a row's owner is not established (R6).
-- One user meaning per label: the panel's menu button is "Options" (#165),
-- the Build Library scope is "Mine" (the game's own page keeps "My Builds"),
-- Help gives the same words, and an offline terminology lint keeps the
-- deprecated unqualified forms out of the player-facing UI sources, with
-- explicit, reasoned exceptions instead of blind global replacement.
-- Categories (view_regression_support): EXPECT is behaviour added in M4 (it
-- fails on the accepted M3 cut ab3cb307); GUARD already holds there and must
-- keep holding; SETUP is the fixture. Oracles: the real panel's fontstrings and
-- its hit frames' own OnEnter tooltips, the real Leaderboard detail pane and
-- status line, the Help body, the UI source files as shipped, and
-- game-action/send/request counters. Panel records are rendered by its real
-- Render from the published model with only the record fields varied.
-- Real TOC boot; synthetic host services and records only. No native, LK
-- reception or ranking claim.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local C=V.Checker('ux_record_scope_terms')
local H,A
local E2={{spellId=201175,quality=0,stacks=1}}
local EF={{spellId=201174,quality=0,stacks=1}}
-- 2023-11-14 22:13:20 UTC.
local STAMP=1700000000

local function Boot()
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
 ProjectEbonholdEchoJournal=nil;NexusEditorFrame=nil;NexusPanel=nil
 H=dofile('tests/prototype/harness.lua')
 H.playerLevel=60
 wipe(H.db)
 H.AddEcho(201174,'Echo Free',0,5);H.AddEcho(201175,'Echo Fire',0,5)
 H.service.GetServerMaxSlots=function() return 6 end
 H.perks.serverBuildSlots={[2]={name='Fire PvE',verified=true,echoes=H.Clone(E2)},
  [107]={name='W-Free',verified=false,echoes=H.Clone(EF)}}
 H.perks.serverActiveSlot=2
 ProjectEbonhold.OrbService={IsStateKnown=function()return true end,GetCharges=function()return 0 end,
  IsOfferPending=function()return false end,RequestCharges=function()end,
  ConfirmSpend=function() error('reading records must not spend') end}
 H.Boot();A=Nexus.GameAdapter
 H.Notify();A.Poll();H.Advance(1)
 if NexusQuickStart and NexusQuickStart:IsShown() then NexusQuickStart:Hide() end
end
local function Effects() return {actions=#H.actions,sent=#H.sent,granted=tonumber(H.grantedRequests) or 0} end
local function Same(a,b) return a.actions==b.actions and a.sent==b.sent and a.granted==b.granted end
local function PanelTexts()
 local out={}
 for _,r in ipairs(NexusPanel and NexusPanel.regions or {}) do
  if r.GetText and r:IsShown() then local t=r:GetText();if type(t)=='string' and t~='' then out[#out+1]=V.Plain(t) end end
 end
 return out
end
local function Joined(list) return table.concat(list,'\n') end
-- The tooltip a panel hit frame shows through its own OnEnter, chosen by its
-- first line ("Training Dummy" / "Lich King").
local function HitTip(title)
 for _,f in ipairs(NexusPanel and NexusPanel.children or {}) do
  local enter=f.GetScript and f:GetScript('OnEnter')
  if enter and f.kind=='Frame' then
   local lines=V.TooltipLines(function() enter(f) end)
   if V.Plain(lines[1] or '')==title then return V.Plain(table.concat(lines,'\n')) end
  end
 end
 return ''
end
-- The published model with only its records (and counts) varied.
local function RenderRecords(complete)
 local model=H.Clone(Nexus.Panel._lastModel)
 model.progress=model.progress or {}
 model.progress.owned,model.progress.total=complete and 79 or 12,79
 model.progress.toLock={};model.progress.missing={};model.progress.unknownTomes={}
 model.progress.wishlistName=model.progress.wishlistName or 'W-Free'
 model.progress.performance={
  dummy={personal={dps=12000,duration=95},
   global={dps=25000,player='Alpha',duration=180,level=80,ts=STAMP,ownerVerified=false}},
  -- A record that carries no duration, level, date or owner flag.
  lk={global={dps=31000,player='Bravo'}},
 }
 model.cards={};model.recommendation=nil;model.orbGuidance=nil;model.autoNote=nil
 return Nexus.Panel.Render(model)==true
end
local function ShowRecords()
 local captured
 EasyMenu=function(items) captured=items end
 CloseDropDownMenus=CloseDropDownMenus or function() end
 local button=NexusPanel and NexusPanel._menuBtn
 if button then button:GetScript('OnClick')(button) end
 for _,item in ipairs(captured or {}) do
  if item.text=='Manage' and item.hasArrow then
   for _,entry in ipairs(item.menuList or {}) do
    if entry.text=='Show DPS records' and type(entry.func)=='function' then entry.func();return true end
   end
  end
 end
 return false
end

C.scenario('R1 panel records: best known for these Echoes, real facts only, owner flag kept',function()
 Boot()
 C.setup(A.SetLoadoutWishlist(2,107)==true,'R1: fixture: Saved Build 2 is assigned W-Free')
 Nexus.Panel.Show();if Nexus.RequestRecompute then Nexus.RequestRecompute() end;H.Notify();H.Advance(1)
 C.setup(type(Nexus.Panel._lastModel)=='table' and ShowRecords(),'R1: fixture: the panel shows DPS records (its own menu item)')
 C.setup(RenderRecords(false),'R1: fixture: the panel renders two shared records')
 local texts=Joined(PanelTexts())
 print('OBSERVED','R1 texts='..texts:gsub('\n',' | '))
 C.expect(texts:find('Best known  25k',1,true)~=nil and texts:find('Best known  31k',1,true)~=nil,
  'R1: the shared column is labelled Best known',texts)
 C.expect(not texts:find('Global',1,true),'R1: no record is labelled Global',texts)
 local before=Effects()
 local dummy,lk=HitTip('Training Dummy'),HitTip('Lich King')
 print('OBSERVED','R1 dummy tip='..dummy:gsub('\n',' | '))
 print('OBSERVED','R1 lk tip='..lk:gsub('\n',' | '))
 C.setup(dummy~='' and lk~='','R1: fixture: both record hit frames show their tooltips')
 C.expect(dummy:find('not a complete or server-wide ranking',1,true)~=nil and lk:find('not a complete or server-wide ranking',1,true)~=nil,
  'R1: both tooltips say the record is what this client knows, not a complete ranking',dummy)
 C.expect(dummy:find('3:00 fight',1,true)~=nil and dummy:find('Level 80',1,true)~=nil
  and dummy:find('Recorded 2023-11-14 (UTC)',1,true)~=nil,'R1: the record\'s own duration, level and date are shown',dummy)
 C.expect(dummy:find('Owner identity not established',1,true)~=nil,'R1: an unverified owner is said so',dummy)
 C.guard(not lk:find('Level 0',1,true) and not lk:find('Owner',1,true),
  'R1: a record without those facts shows no Level 0 and claims no owner state',lk)
 C.guard(Same(Effects(),before),'R1: hovering records sends, requests and acts nothing')
end)

C.scenario('R2 the completed layout labels the shared column the same way',function()
 C.setup(RenderRecords(true),'R2: fixture: the panel renders a completed build with records shown')
 local texts=Joined(PanelTexts())
 print('OBSERVED','R2 texts='..texts:gsub('\n',' | '))
 C.expect(texts:find('Best known',1,true)~=nil and not texts:find('Global Best',1,true),
  'R2: the completed layout says Best known, not Global Best',texts)
end)

C.scenario('R3 the menu button has one name, and Help uses the same words',function()
 local button=NexusPanel and NexusPanel._menuBtn
 local lines=button and V.TooltipLines(function() button:GetScript('OnEnter')(button) end) or {}
 local tip=V.Plain(table.concat(lines,'\n'))
 print('OBSERVED','R3 menu tip='..tip:gsub('\n',' | '))
 -- Issue #165: the control shows "Options" and its hover is headed by that
 -- same visible name (Panel.OptionsLabel), never by a name the panel does not
 -- show (panel_options_label checks the hover drops "Menu and status").
 local shown=button and V.Plain(button:GetText() or '') or ''
 C.expect(V.Plain(lines[1] or '')=='Options' and shown:find('Options',1,true)~=nil
  and not tip:find('Nexus Settings',1,true) and not tip:find('Menu and status',1,true),
  'R3: the menu button has one name, Options, on the control and its hover',tip)
 local before=Effects()
 if Nexus.Help and Nexus.Help.Show then Nexus.Help.Show('start') end
 local body=V.Plain(NexusHelpWindow and NexusHelpWindow.body and NexusHelpWindow.body:GetText() or '')
 C.expect(body:find('Best known: the best shared DPS record this client holds',1,true)~=nil
  and body:find('Options: the Options button on the Nexus panel header',1,true)~=nil
  and not body:find('Menu and status: the ... button',1,true)
  and body:find("My Builds is the game's page of your Saved Builds",1,true)~=nil
  and body:find('the Mine scope lists your Saved Builds and shared listings',1,true)~=nil,
  'R3: Help names Best known, the Options button, the game\'s My Builds page and the Mine scope',body:sub(-700))
 C.guard(Same(Effects(),before),'R3: opening Help sends, requests and acts nothing')
end)

C.scenario('R4 the Leaderboard says its scope and shows only the facts a record carries',function()
 local fx=L.New({players={
  {name='Alpha',class='MAGE',dps={dummy=40000},locked=0},
  {name='Bravo',class='PRIEST',dps={dummy=30000},locked=0},
 }})
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusLeaderboardFrame=nil;NexusPanel=nil
 H=F.Boot(fx:Install(F.Database()))
 for _=1,200 do H.Advance(.05,.05) end
 C.setup(Nexus.StartupStatus().coreReady==true,'R4: fixture: start-up reached core-ready')
 local before=Effects()
 L.Open(H,'dummy')
 local frame=NexusLeaderboardFrame
 -- The status line names the scope while no sync work is shown (the same
 -- line on both cuts; only its words differ).
 local function Status()
  for _,r in ipairs(frame and frame.regions or {}) do
   local t=r.GetText and V.Plain(r:GetText() or '') or ''
   if t:find('exact loadout per character',1,true) then return t end
  end
  return nil
 end
 local status
 for _=1,400 do status=Status();if status then break end;H.Advance(.05,.05) end
 C.setup(status~=nil,'R4: fixture: the Leaderboard shows its idle scope line',status)
 status=status or ''
 print('OBSERVED','R4 status='..status)
 C.expect(status=='Best known exact loadout per character','R4: the list says it is the best known per character',status)
 local d=L.Select(H,1)
 local record=V.Plain(d.record or '')
 print('OBSERVED','R4 record='..record:gsub('\n',' | '))
 C.setup(record:find('DPS',1,true)~=nil and record:find('Training Dummy',1,true)~=nil,'R4: fixture: the detail pane shows the record',record)
 C.expect(record:find('3:00 fight',1,true)~=nil and record:find('Level 80',1,true)~=nil and record:find('Recorded ',1,true)~=nil,
  'R4: the detail shows the record\'s duration, level and recorded date',record)
 C.guard(not record:find('Level 0',1,true),'R4: no Level 0 is shown',record)
 C.guard(Same(Effects(),before),'R4: opening and selecting performs no game action or send')
end)

-- Offline terminology lint over the player-facing UI sources as shipped.
-- Each rule names a deprecated unqualified form, optionally only in the files
-- where that form has the deprecated meaning (no blind global replacement:
-- "My Builds" stays where it names the game's own page). An exception would
-- name the exact file, phrase and reason; the two earlier "right away"
-- exceptions (Journal tooltip, Help) were retired when that copy was changed
-- to the traced check behaviour (M3 FN7/OD4), so none remains.
local UI_FILES={'ui/Panel.lua','ui/Leaderboard.lua','ui/CommunityRenderer.lua','ui/CommunityBuilds.lua',
 'ui/Help.lua','ui/QuickStart.lua','ui/OrbPanel.lua','ui/WishlistRenderer.lua','ui/WishlistEditor.lua',
 'ui/JournalTab.lua','ui/Readout.lua',
 -- Issues #143/#148: the reviewed English base now holds the Panel's moved
 -- labels and hovers, so that shipped player-facing copy stays linted.
 'data/LocalizationEnglish.lua'}
local RULES={
 {phrase='Global Best',why='a shared record is the best known to this client, not a global ranking (UX-14)'},
 {phrase='"Global  ',why='the compact shared column is Best known (UX-14)'},
 {phrase='/ %d complete',why='a run count is rolled copies this run; complete needs every category (UX-13)'},
 {phrase='in progress|r',why='the Saved Build card counts Wishlist copies in this Saved Build (UX-13)'},
 {phrase='Nexus Settings',why='the menu button is Options (UX-15, #165)'},
 {phrase='within seconds',why='no replacement latency is promised (UX-05/UX-15)'},
 {phrase='right away',why='no replacement latency is promised; the copy states the check trigger (FN7/OD4)'},
 {phrase='"My Builds"',files={['ui/CommunityRenderer.lua']=true},why='the Build Library scope is Mine; My Builds is the game\'s page (UX-15)'},
 {phrase='All Shared and My Builds',files={['ui/Help.lua']=true},why='Help names the Build Library scope Mine (UX-15)'},
 {phrase='deleting from My Builds',files={['ui/Help.lua']=true},why='Help names the Build Library scope Mine (UX-15)'},
 {phrase='Open My Builds and browse',files={['ui/Panel.lua']=true,['data/LocalizationEnglish.lua']=true},why='Build Library is not the game\'s My Builds page (UX-15)'},
 -- Final copy closure (UX-13/UX-15): the editor footer and the save notice
 -- count planned rolled copies; an unnamed or empty selector row is a Saved
 -- Build, not a Loadout.
 {phrase='"Rolled copies: "',files={['ui/WishlistRenderer.lua']=true},why='the editor footer counts planned rolled copies (UX-13)'},
 {phrase='name = "Loadout " .. tostring(slot)',files={['ui/WishlistRenderer.lua']=true},why='an unnamed Saved Build row is Saved Build N (UX-15)'},
 {phrase='|cff666666Loadout " .. tostring(targetSlot)',files={['ui/WishlistRenderer.lua']=true},why='an empty Saved Build row is Saved Build N (UX-15)'},
 {phrase='/79 rolled copies; ',files={['core/WishlistController.lua']=true},why='the save notice counts planned rolled copies (UX-13)'},
}
-- Read only for the file-scoped rules above (not UI: no other rule applies).
local SCOPED_FILES={'core/WishlistController.lua'}
local EXCEPTIONS={}
local function Excepted(file,phrase)
 for _,e in ipairs(EXCEPTIONS) do if e.file==file and e.phrase==phrase then return true end end
 return false
end
-- Where "My Builds" names the game's own page it stays (one meaning, kept).
-- Issues #143/#148: the Panel's My Builds button and its hover now show
-- reviewed keys, and a selected pack may translate that navigation label.
-- Each Panel entry is its actual binding in ui/Panel.lua plus the exact
-- English the real seam gives the key, stated here as an independent literal
-- (not read from the data); the hover still names the server's own My Builds
-- page. The other file keeps its source literal.
local GAME_PAGE_LABELS={{file='ui/Panel.lua',phrase='switchBtn:SetText((Nexus.Localization.Text("panel.button.my_builds")))',
  key='panel.button.my_builds',english='My Builds'},
 {file='ui/Panel.lua',phrase='GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.open_my_builds")',
  key='panel.tooltip.open_my_builds',english='Open My Builds'},
 {file='ui/Panel.lua',phrase='GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.my_builds_destination")',
  key='panel.tooltip.my_builds_destination',
  english='Open the server My Builds page. Choosing a different Saved Build there changes the active loadout.'},
 {file='ui/JournalTab.lua',phrase='"Assign in My Builds"'}}

C.scenario('R5 terminology lint: no deprecated unqualified form in the shipped UI sources',function()
 local found,read,sources={},0,{}
 for _,file in ipairs(UI_FILES) do
  local handle=io.open(file,'rb')
  if handle then
   read=read+1
   local source=handle:read('*a');handle:close()
   sources[file]=source
   for _,rule in ipairs(RULES) do
    if (not rule.files or rule.files[file]) and source:find(rule.phrase,1,true) and not Excepted(file,rule.phrase) then
     found[#found+1]=file..': "'..rule.phrase..'" ('..rule.why..')'
    end
   end
  end
 end
 for _,file in ipairs(SCOPED_FILES) do
  local handle=io.open(file,'rb')
  if handle then
   read=read+1
   local source=handle:read('*a');handle:close()
   for _,rule in ipairs(RULES) do
    if rule.files and rule.files[file] and source:find(rule.phrase,1,true) and not Excepted(file,rule.phrase) then
     found[#found+1]=file..': "'..rule.phrase..'" ('..rule.why..')'
    end
   end
  end
 end
 C.setup(read==#UI_FILES+#SCOPED_FILES,'R5: fixture: every listed source was read',read)
 print('OBSERVED','R5 lint='..(#found>0 and table.concat(found,'; ') or 'clean'))
 C.expect(#found==0,'R5: no deprecated unqualified form remains outside the named exceptions',table.concat(found,'; '))
 -- No blind replacement: the game's own My Builds page keeps its name.
 local missing={}
 for _,g in ipairs(GAME_PAGE_LABELS) do
  local kept=(sources[g.file] or ''):find(g.phrase,1,true)~=nil
  if kept and g.key then
   local text,source,why=Nexus.Localization.Resolve(g.key)
   kept=Nexus.Localization.Kind(g.key)=='text' and text==g.english and source=='base' and why==nil
  end
  if not kept then missing[#missing+1]=g.file..': '..g.phrase..(g.key and (' = '..g.english) or '') end
 end
 C.guard(#missing==0,'R5: the game\'s own My Builds page keeps its name where it means that page',table.concat(missing,'; '))
 -- The actual bound button in this English session, and its unchanged
 -- destination: the real Panel's My Builds button shows exactly My Builds,
 -- and its click still opens the game's own My Builds page through the
 -- deferred close callback. A refused game-page open must leave Plan intact.
 Nexus.Panel.Show()
 local switch=NexusPanel and NexusPanel._switchBtn
 local shown=switch and V.Plain(switch:GetText() or '') or ''
 local journal=Nexus.JournalTab
 local openBuilds,calls=journal and journal.OpenBuilds,{}
 if journal then journal.OpenBuilds=function(deferred,close,...)
  calls[#calls+1]={deferred=deferred,close=close,extra=select('#',...)}
  return true
 end end
 local clicked=switch~=nil and pcall(switch.Click,switch)
 if journal then journal.OpenBuilds=openBuilds end
 C.guard(Nexus.Localization.ActiveLanguage()=='enUS' and shown=='My Builds' and clicked==true
  and #calls==1 and calls[1].deferred==false and type(calls[1].close)=='function' and calls[1].extra==0,
  'R5: the My Builds button keeps its name and guarded game-page route',shown..' / '..#calls..' call(s)')
end)

-- R6: the real Build Library window. The Mine scope (internal key "mine"),
-- a card's best-DPS headline that names its category, and a row whose owner
-- is not established saying so. Synthetic records: a verified remote build
-- with both records (leaderboard fixture) and a relayed build stored without
-- an established owner (the real relay admission, as public_label_presentation
-- stores it). Display only: no score, ranking, owner or provenance change.
C.scenario('R6 Build Library: Mine scope, category-named headline, owner not established on the row',function()
 local fx=L.New({players={
  {name='Bothdps',class='MAGE',dps={dummy=43000,lk=44000},locked=0},
 }})
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil;NexusCommunityBuildsFrame=nil;NexusPanel=nil
 H=F.Boot(fx:Install(F.Database()))
 for _=1,200 do H.Advance(.05,.05) end
 C.setup(Nexus.StartupStatus().coreReady==true,'R6: fixture: start-up reached core-ready')
 local both
 for _,p in ipairs(fx.players) do if p.name=='Bothdps' then both=p.buildId end end
 -- A relayed build without an established owner (real catalog admission).
 local relayed='relay-r6-unverified'
 local rec={id=relayed,title='Relayed build R6',author='Kiralyl',ownerKey='kiralyl@ebonhold',realm='ebonhold',class='MAGE',
  postedAt=L.STAMP+800,lastModified=L.STAMP+800,description='Synthetic relayed build',echoes=L.OrdinaryRows(22,30)}
 local ok,why,ticket
 for _=1,400 do
  ok,why,ticket=Nexus.BuildCatalog.Put(rec,{source='remote',sender='Relayer-Ebonhold'})
  if ok==nil and type(ticket)=='table' then
   for _=1,4000 do if ticket.state~='pending' then break end;H.Advance(.05,.05) end
   ok,why=ticket.committed==true,ticket.reason or ticket.state
  end
  if why~='ROOT_MUTATION_PENDING' and why~='ROOT_ADMISSION_PENDING' then break end
  for _=1,20 do H.Advance(.05,.05) end
 end
 local stored=Nexus.BuildCatalog.Get(relayed)
 C.setup(both~=nil and ok==true and stored and stored.ownerVerified==false,
  'R6: fixture: a verified build with both records and a relayed build without an established owner')
 local before=#H.actions
 Nexus.CommunityBuilds.Show()
 for _=1,200 do H.Advance(.05,.05) end
 local frame=NexusCommunityBuildsFrame
 local box=frame and frame._qualifiedBtn
 if box and box:GetChecked() then box:SetChecked(false);box:Click() end
 local settled=false
 for _=1,4000 do
  local d=Nexus.CommunityBuilds.DiagnosticSnapshot()
  if d.filterQualifiedOnly==false and d.projectionCurrent and not d.projectionPending and not d.projectionDirty then settled=true;break end
  H.Advance(.05,.05)
 end
 C.setup(settled,'R6: fixture: the All Shared list shows builds without both records too')
 local cards={}
 for step=0,20 do
  Nexus.CommunityBuilds.ScrollTo(step*92);for _=1,3 do H.Advance(.05,.05) end
  for _,f in ipairs(H.frames) do
   if f.buildId and f:IsVisible() and f.author and f.echoCount and not cards[f.buildId] then
    cards[f.buildId]={author=V.Plain(f.author:GetText() or ''),headline=V.Plain(f.echoCount:GetText() or '')}
   end
  end
 end
 Nexus.CommunityBuilds.ScrollTo(0);H.Advance(.05,.05)
 local b,r=cards[both] or {},cards[relayed] or {}
 print('OBSERVED','R6 both headline='..tostring(b.headline)..' author='..tostring(b.author))
 print('OBSERVED','R6 relayed author='..tostring(r.author))
 C.setup(cards[both]~=nil and cards[relayed]~=nil,'R6: fixture: both cards are bound by the real list')
 C.expect((b.headline or ''):find('Best ',1,true)~=nil and (b.headline or ''):find('(Lich King)',1,true)~=nil,
  'R6: the best-DPS headline names its category (the higher Lich King record)',b.headline)
 C.expect((r.author or ''):find('Owner not established',1,true)~=nil,'R6: the row of a build without an established owner says so',r.author)
 C.guard(not (b.author or ''):find('Owner not established',1,true),'R6: a verified owner\'s row carries no such tag',b.author)
 local mine=frame and frame._myBuildsBtn
 local tip=mine and V.TooltipLines(function() mine:GetScript('OnEnter')(mine) end) or {}
 local text=mine and V.Plain(mine:GetText() or '') or ''
 print('OBSERVED','R6 scope button='..text..' tip='..V.Plain(table.concat(tip,' | ')))
 C.expect(text=='Mine' and V.Plain(tip[1] or '')=='Mine' and V.Plain(table.concat(tip,'\n')):find("game's own My Builds page",1,true)~=nil,
  'R6: the Build Library scope is called Mine and is told apart from the game\'s My Builds page',text)
 if mine then mine:Click() end
 C.guard(Nexus.CommunityBuilds.DiagnosticSnapshot().filterScope=='mine','R6: the Mine button still selects the internal mine scope')
 C.guard(#H.actions==before,'R6: opening, filtering and hovering the Build Library performs no game action',#H.actions)
end)

C.finish('(records say best known with real facts, category and owner flags; one name per label; deprecated forms linted without blind replacement)')
