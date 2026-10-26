-- Issue #163 (UI review prototype): one status vocabulary, the grouped ...
-- menu with every earlier label kept, and the Plan / Explore / Orbs footer
-- hubs that only open existing windows. Categories (view_regression_support):
-- EXPECT is behaviour added by this change (it fails on 34229edf by design:
-- no Readout vocabulary, no menu groups, no hubs); GUARD already held there
-- and must keep holding; SETUP is the fixture. Oracles: the real Readout and
-- OrbHistory tables, the ... menu and hub menus as EasyMenu receives them,
-- the hubs' own handlers and hovers, the anchors of the real footer buttons
-- (layout_geometry_support), and game-action, send, settings, assignment and
-- Auto counters. Window owners are spied where a route is checked; the Orb
-- window opens for real. Real TOC boot; synthetic host services only.
-- Native pixels, label fit at large font scales, dropdown drawing and
-- keyboard input are NOT RUN.
local V=dofile('tests/prototype/view_regression_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('ui_review_navigation')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local R,P=Nexus.Readout,Nexus.Panel
local bootActions=#H.actions

local function Effects()
 local state=Nexus.Store and Nexus.Store.State and Nexus.Store.State() or {}
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'saved='..F.Serialize(NexusDB),
  'assignments='..F.Serialize(type(state.loadoutWishlists)=='table' and state.loadoutWishlists or {}),
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
local function Capture(fn)
 local captured
 local easy,close=EasyMenu,CloseDropDownMenus
 EasyMenu=function(items) captured=items end
 CloseDropDownMenus=function() end
 local ok,err=pcall(fn)
 EasyMenu,CloseDropDownMenus=easy,close
 assert(ok,err)
 return captured
end
local function Item(items,text)
 for _,item in ipairs(items or {}) do if item.text==text then return item end end
 return nil
end
local function Prefixed(items,prefix)
 local found={}
 for _,item in ipairs(items or {}) do
  if type(item.text)=='string' and item.text:sub(1,#prefix)==prefix then found[#found+1]=item end
 end
 return found
end
local function Texts(items)
 local t={}
 for _,item in ipairs(items or {}) do t[#t+1]=tostring(item.text) end
 return table.concat(t,' / ')
end
-- Replace fn on owner for one call of body; count the calls and keep the
-- arguments of the last one.
local function Spy(owner,key,body)
 local real=owner[key]
 local spy={n=0}
 owner[key]=function(...) spy.n=spy.n+1;spy.args={n=select('#',...),...};return true end
 local ok,err=pcall(body)
 owner[key]=real
 assert(ok,err)
 return spy
end
local function Model(o)
 o=o or {}
 return {status='ready',level=o.level or 40,auto=o.auto==true,cards={},recommendation='',
  progress={wishlistName=not o.noBuild and 'Synthetic navigation plan' or nil,total=o.noBuild and 0 or 6,
   owned=1,missing={},shed={},toLock={},unknownTomes={}}}
end
local function Rect(region) local ok,r=pcall(G.Rect,region,NexusPanel);return ok and r or nil end

C.scenario('V1 one status vocabulary: a glyph and a word per kind; unknown is never a success or zero',function()
 C.expect(R and type(R.StatusParts)=='function' and type(R.StatusText)=='function' and type(R.CountText)=='function'
  and type(R.STATUS_KINDS)=='table','V1: Readout offers the shared status vocabulary')
 if not (R and type(R.STATUS_KINDS)=='table') then return end
 local seen,bad={},{}
 for _,kind in ipairs(R.STATUS_KINDS) do
  local s=R.StatusParts(kind)
  if seen[kind] then bad[#bad+1]=kind..' listed twice' end
  seen[kind]=true
  if s.kind~=kind or type(s.glyph)~='string' or s.glyph=='' or s.glyph:find('[^\32-\126]')
   or s.glyph:find('|',1,true) or type(s.word)~='string' or s.word=='' then
   bad[#bad+1]=kind
  end
  if R.StatusText(kind)~=s.glyph..' '..s.word then bad[#bad+1]=kind..' text' end
 end
 C.expect(#bad==0,'V1: every kind has a printable ASCII glyph (no pipe) and a word, shown together',table.concat(bad,', '))
 C.expect(R.StatusText('confirmed')=='+ Confirmed' and R.StatusText('awaiting')=='... Awaiting result'
  and R.StatusText('estimated')=='~ Estimated' and R.StatusText('unavailable','reason')=='! Unavailable: reason',
  'V1: the words read as written',R.StatusText('confirmed'))
 C.expect(R.StatusText('no such kind')=='? Unknown' and R.StatusText(nil)=='? Unknown'
  and R.StatusParts({}).kind=='unknown','V1: an unlisted kind is said as unknown',R.StatusText('no such kind'))
 local counts={R.CountText(nil),R.CountText('x'),R.CountText(0/0),R.CountText(-1),R.CountText(math.huge),
  R.CountText(0),R.CountText(3.6),R.CountText(12,true)}
 C.expect(counts[1]=='?' and counts[2]=='?' and counts[3]=='?' and counts[4]=='?' and counts[5]=='?'
  and counts[6]=='0' and counts[7]=='4' and counts[8]=='~12',
  'V1: a missing or invalid count is "?", never 0; zero stays 0; an estimate carries "~"',table.concat(counts,','))
 -- Each recorded state names a vocabulary kind, whose word is its label.
 local mismatched={}
 for state,entry in pairs(Nexus.OrbHistory.RESULTS) do
  if type(entry.status)~='string' or not seen[entry.status] or R.StatusParts(entry.status).word~=entry.label then
   mismatched[#mismatched+1]=state
  end
 end
 C.expect(#mismatched==0,'V1: every recorded Orb state maps to a vocabulary kind with its own label',table.concat(mismatched,', '))
 local odd=Nexus.OrbHistory.Result({state='not a recorded state'})
 C.expect(odd.status=='unconfirmed' and odd.label=='Unconfirmed' and not odd.confirmed,
  'V1: an unrecorded Orb state stays unconfirmed, never confirmed',odd.status)
 C.guard(Nexus.OrbHistory.Result({state='confirmed',obtained='410002:2'}).label=='Confirmed'
  and Nexus.OrbHistory.Result({state='confirmed'}).label=='Unconfirmed'
  and Nexus.OrbHistory.Result({state='requested'}).label=='Request prepared'
  and Nexus.OrbHistory.Result({state='selected'}).label=='Awaiting result',
  'V1: the Orb history requires obtained identity to confirm and never calls a prepared request sent')
 C.guard(R.ChargesLine({banish=1,reroll=nil,freeze=0})=='B:1 R:? F:0','V1: the charges row keeps "?" for an unreported count')
end)

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
Nexus.DisableOrdinaryAutomation()
P.Show()
C.setup(P.Render(Model())==true and NexusPanel and NexusPanel:IsShown(),'fixture: the real HUD renders a build in progress with Auto OFF')

C.scenario('V2 the ... menu is grouped and keeps every earlier label and handler',function()
 local before=Effects()
 local menu=NexusPanel._menuBtn
 local items=Capture(function() menu:GetScript('OnClick')(menu) end)
 C.setup(type(items)=='table' and #items>0,'V2: fixture: the ... menu opens',Texts(items))
 print('OBSERVED','V2 menu='..Texts(items))
 local missing={}
 for _,label in ipairs({'Help / Getting Started','Setup / Welcome','Setup checklist and status','Orbs / Lost Memories',
  'Automation settings','Wishlist Editor','Reset Panel Position','Hide Nexus Panel'}) do
  local item=Item(items,label)
  if not (item and type(item.func)=='function' or item and item.hasArrow) then missing[#missing+1]=label end
 end
 for _,prefix in ipairs({'Language','Appearance: ','Update notices: '}) do
  if #Prefixed(items,prefix)~=1 then missing[#missing+1]=prefix..'*' end
 end
 if not (Item(items,'Show DPS records') or Item(items,'Hide DPS records')) then missing[#missing+1]='DPS records' end
 if not (Item(items,'Disable Update Notices') or Item(items,'Enable Update Notices')) then missing[#missing+1]='Update Notices' end
 if not (Item(items,'Use Server Difficulty / Soul Ash HUD') or Item(items,'Use Nexus Difficulty / Soul Ash HUD')) then
  missing[#missing+1]='HUD mode'
 end
 C.guard(#missing==0,'V2: every earlier entry is still one click away under its own label',table.concat(missing,', '))
 local order,last,unordered={'Help and setup','Settings','Notices','Logs','Also on the panel footer','Panel'},0,{}
 for _,title in ipairs(order) do
  local at
  for index,item in ipairs(items) do if item.text==title and item.isTitle==true and item.notCheckable==true then at=index end end
  if not at or at<=last then unordered[#unordered+1]=title end
  last=at or last
 end
 C.expect(#unordered==0,'V2: the menu is grouped under titled sections, in order',table.concat(unordered,', '))
 local help,orbs,hide=Item(items,'Help / Getting Started'),Item(items,'Orbs / Lost Memories'),Item(items,'Hide Nexus Panel')
 local function Index(item) for i,x in ipairs(items) do if x==item then return i end end end
 local function Under(item,title,nextTitle)
  local a,b=Index(Item(items,title)),nextTitle and Index(Item(items,nextTitle)) or #items+1
  local i=Index(item)
  return a and i and b and a<i and i<b
 end
 C.expect(Under(help,'Help and setup','Settings') and Under(orbs,'Also on the panel footer','Panel') and Under(hide,'Panel'),
  'V2: help, the footer aliases and the panel actions sit in their groups')
 C.expect(orbs and orbs.tooltipText=='Also Orbs on the panel footer.' and hide and type(hide.tooltipText)=='string'
  and hide.tooltipText:find('/nexus panel',1,true)~=nil,'V2: moved and hiding entries say where else they are and how the panel returns')
 C.expect(hide and not hide.tooltipText:find('The Nexus panel is hidden',1,true),
  'V2: the pre-click Hide tooltip does not claim the still-visible panel is already hidden',hide and hide.tooltipText)
 local support,logs=Item(items,'Support report...'),Item(items,'Log viewer...')
 C.expect(support and type(support.func)=='function' and logs and type(logs.func)=='function',
  'V2: Support report and the log viewer are reachable from the menu')
 C.guard(Effects()==before,'V2: opening the menu keeps measured actions, sends, saved data, assignments and Auto unchanged',Effects())
 if support then
  local spy=Spy(Nexus.SupportReportUI,'Show',function() support.func() end)
  C.expect(spy.n==1,'V2: Support report... opens the existing support page (/nexus report)',spy.n)
 end
 if logs then
  local spy=Spy(Nexus.LogViewer,'Show',function() logs.func() end)
  C.expect(spy.n==1,'V2: Log viewer... opens the existing log viewer (/nexus log)',spy.n)
 end
 local editor=Item(items,'Wishlist Editor')
 if editor then
  local spy=Spy(Nexus.WishlistEditor,'Show',function() editor.func() end)
  C.guard(spy.n==1,'V2: the kept Wishlist Editor entry opens the editor',spy.n)
 end
 C.guard(Effects()==before,'V2: the navigation entries act, send and change nothing',Effects())
 if hide then
  local lines,realPrint={},print
  print=function(...) local t={} for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end lines[#lines+1]=table.concat(t,' ') end
  local ok,err=pcall(hide.func)
  print=realPrint
  C.setup(ok,'V2: fixture: the Hide Nexus Panel entry runs',err)
  local said=table.concat(lines,'\n')
  C.guard(not NexusPanel:IsShown() and P.VisibilityFacts().wanted==false,'V2: Hide Nexus Panel still hides the panel')
  C.expect(said:find('Hiding does not turn Nexus off or change Auto',1,true)~=nil and said:find('/nexus panel',1,true)~=nil,
   'V2: hiding says it is not turning Nexus off and how to show the panel again',said)
  C.guard(Effects()==before,'V2: hiding keeps measured actions, sends, saved data, assignments and Auto unchanged',Effects())
  P.Show()
  C.setup(NexusPanel:IsShown(),'V2: fixture: the panel shows again')
 end
end)

C.scenario('V3 the footer: Auto apart, then Plan, Explore and Orbs inside the 272 px HUD',function()
 C.setup(P.Render(Model())==true,'V3: fixture: a build in progress with Auto shown')
 local f=NexusPanel
 local hubs=f._footerButtons or {}
 C.expect(hubs.plan and hubs.explore and hubs.orbs and hubs.auto==f._autoBtn,'V3: the footer holds Auto and the three hubs')
 if not (hubs.plan and hubs.explore and hubs.orbs) then return end
 C.expect(V.Plain(hubs.plan:GetText())=='Plan' and V.Plain(hubs.explore:GetText())=='Explore' and V.Plain(hubs.orbs:GetText())=='Orbs',
  'V3: the hubs read Plan, Explore and Orbs')
 local peers={}
 for _,c in ipairs(f.children or {}) do
  if c.kind=='Button' and c:IsShown() then
   local label=V.Plain(c:GetText() or '')
   if label=='Build Library' or label=='Leaderboard' then peers[#peers+1]=label end
  end
 end
 C.expect(#peers==0,'V3: Build Library and Leaderboard are no longer footer peers (Explore holds them)',table.concat(peers,', '))
 C.guard(f:GetWidth()==272,'V3: the HUD keeps its 272 px width',f:GetWidth())
 local a,p,e,o=Rect(hubs.auto),Rect(hubs.plan),Rect(hubs.explore),Rect(hubs.orbs)
 C.setup(a and p and e and o,'V3: fixture: every footer control resolves its anchors')
 if not (a and p and e and o) then return end
 print('OBSERVED','V3 auto='..G.Text(a)..' plan='..G.Text(p)..' explore='..G.Text(e)..' orbs='..G.Text(o))
 C.guard(hubs.auto:IsShown() and a[1]==8 and a[3]-a[1]==72,'V3: Auto keeps its place and size',G.Text(a))
 C.expect(p[1]-a[3]>=10 and e[1]-p[3]>=3 and o[1]-e[3]>=3,'V3: Auto stands apart from the hubs, which do not touch',
  G.Text(a)..' '..G.Text(p)..' '..G.Text(e)..' '..G.Text(o))
 C.expect(o[3]<=272-8 and G.Apart(a,p) and G.Apart(p,e) and G.Apart(e,o),'V3: all four stay inside the HUD margin, apart',G.Text(o))
 C.setup(P.Render(Model({noBuild=true}))==true,'V3: fixture: the setup view (no build) renders')
 a,p,e,o=Rect(hubs.auto),Rect(hubs.plan),Rect(hubs.explore),Rect(hubs.orbs)
 C.guard(not hubs.auto:IsShown(),'V3: without a build the Auto control stays hidden, as before')
 C.expect(hubs.plan:IsShown() and hubs.explore:IsShown() and hubs.orbs:IsShown() and p and e and o
  and p[1]>=8 and o[3]<=272-8 and G.Apart(p,e) and G.Apart(e,o),'V3: the three hubs share the row without Auto',
  p and e and o and (G.Text(p)..' '..G.Text(e)..' '..G.Text(o)) or 'unplaced')
 C.setup(P.Render(Model())==true,'V3: fixture: back to the build in progress')
end)

C.scenario('V4 the hubs open existing routes only; their menus and hovers say so',function()
 local f=NexusPanel
 local hubs=f._footerButtons or {}
 if not (hubs.plan and hubs.explore and hubs.orbs) then C.expect(false,'V4: the hubs exist');return end
 local before=Effects()
 local plan=Capture(function() hubs.plan:Click() end)
 print('OBSERVED','V4 plan='..Texts(plan))
 local editor,assign,builds=Item(plan,'Wishlist Editor'),Item(plan,'Assign Wishlist...'),Item(plan,'My Builds (game page)')
 local note=Item(plan,'Opening a window saves, assigns and loads nothing.')
 C.expect(editor and assign and builds and type(editor.func)=='function' and type(assign.func)=='function'
  and type(builds.func)=='function' and note and note.disabled==true,'V4: Plan lists the editor, assignment and My Builds with a visible no-change note',Texts(plan))
 local explore=Capture(function() hubs.explore:Click() end)
 print('OBSERVED','V4 explore='..Texts(explore))
 local library,board=Item(explore,'Build Library'),Item(explore,'Leaderboard')
 C.setup(Nexus.StartupStatus().state=='ready','V4: fixture: shared start-up finished',Nexus.StartupStatus().state)
 local shared=Item(explore,'+ Ready: shared builds and records')
 C.expect(library and board and type(library.func)=='function' and type(board.func)=='function'
  and shared and shared.disabled==true,'V4: Explore lists the Build Library and Leaderboard and the shared data state',Texts(explore))
 C.expect(#Prefixed(explore,'Best known: ')==1,'V4: Explore says what best known means')
 C.guard(Effects()==before,'V4: opening the hub menus keeps measured actions, sends, saved data, assignments and Auto unchanged',Effects())
 if editor then
  C.expect(Spy(Nexus.WishlistEditor,'Show',function() editor.func() end).n==1,'V4: Plan > Wishlist Editor opens the editor')
 end
 if assign then
  local spy=Spy(Nexus.JournalTab,'OpenBuilds',function() assign.func() end)
  C.expect(spy.n==1 and spy.args[1]==true and type(spy.args[2])=='function',
   'V4: Plan > Assign Wishlist... opens the Journal chooser route, which assigns nothing until a choice',spy.n)
 end
 if builds then
  local spy=Spy(Nexus.JournalTab,'OpenBuilds',function() builds.func() end)
  C.expect(spy.n==1 and spy.args.n==0,'V4: Plan > My Builds opens the game page (the header button route)',spy.n)
 end
 if library then
  C.expect(Spy(Nexus.CommunityBuilds,'Show',function() library.func() end).n==1,'V4: Explore > Build Library opens the library')
 end
 if board then
  C.expect(Spy(Nexus.Leaderboard,'Show',function() board.func() end).n==1,'V4: Explore > Leaderboard opens the leaderboard')
 end
 local header=f._switchBtn
 C.guard(Spy(Nexus.JournalTab,'OpenBuilds',function() header:Click() end).args.n==0,'V4: the header My Builds button keeps its route')
 C.guard(Effects()==before,'V4: every routed entry keeps measured actions, sends, saved data, assignments and Auto unchanged',Effects())
 local realClose,closed=CloseDropDownMenus,0
 CloseDropDownMenus=function() closed=closed+1 end
 local opened,openError=pcall(function() hubs.orbs:Click() end)
 CloseDropDownMenus=realClose
 C.expect(opened and NexusOrbPanel and NexusOrbPanel:IsShown(),'V4: Orbs opens the Orb window directly',openError)
 C.expect(closed==1,'V4: opening Orbs closes any Plan or Explore dropdown',closed)
 C.guard(Effects()==before,'V4: opening the Orb window keeps measured actions, sends, saved data, assignments and Auto unchanged',Effects())
 if NexusOrbPanel then NexusOrbPanel:Hide() end
 for kind,button in pairs({plan=hubs.plan,explore=hubs.explore,orbs=hubs.orbs}) do
  local lines,ok,err=V.TooltipLines(button:GetScript('OnEnter'),button)
  local tip=V.Plain(table.concat(lines,'\n'))
  local want=({plan='saves, assigns and loads nothing',explore='not a complete or server-wide ranking',
   orbs='an approved run continues'})[kind]
  C.expect(ok and tip:find(want,1,true)~=nil,'V4: the '..kind..' hover says '..want,tostring(err)..' '..tip)
 end
 C.guard(Effects()==before,'V4: hovering the hubs keeps measured actions, sends, saved data, assignments and Auto unchanged',Effects())
end)

C.scenario('V5 the hub status lines say only what their passive sources report',function()
 local runtime=Nexus.OrbRuntime
 local view=runtime.ReasonView
 local function Line(v)
  runtime.ReasonView=type(v)=='function' and v or function() return v end
  local ok,text=pcall(P.OrbHubLine)
  runtime.ReasonView=view
  return ok and text or ('raised: '..tostring(text))
 end
 local cases={
  {{observed=false},'? Unknown: the Orb state has not been read this session'},
  {{observed=true,run=false},'Orb run: none approved'},
  {{observed=true,run=true,state='PAUSED',running=false,pending=false,restored=false},'Orb run: Paused'},
  {{observed=true,run=true,state='WAIT_RESULT',running=true,pending=true,restored=false},
   'Orb run: Waiting for result confirmation; ... Awaiting result'},
  {{observed=true,run=true,state='RECOVERY',running=false,pending=true,restored=true},
   'Orb run: Earlier Orb action unresolved; ? Unconfirmed: the action from before reload'},
  {{observed=true,run=true,state='PAUSED',running=false,pending=true,restored=false},
   'Orb run: Paused; an action may still settle'},
  {{observed=true,run=true,state='FUTURE_STATE',running=false,pending=false,restored=false},
   'Orb run: state FUTURE_STATE is not described here'},
  {{observed=true,run=true,pending=false},'Orb run: state not recorded'},
  {function() error('synthetic read failure') end,'? Unknown: the Orb run cannot be read now'},
 }
 for index,case in ipairs(cases) do
  local got=Line(case[1])
  C.expect(got==case[2],'V5: Orb case '..index..' reads '..case[2],got)
  C.guard(not got:find('+ Confirmed',1,true) and not got:lower():find('spent',1,true),'V5: Orb case '..index..' claims no confirmed spend',got)
 end
 local status=Nexus.StartupStatus
 local function Shared(s)
  Nexus.StartupStatus=type(s)=='function' and s or function() return s end
  local ok,text=pcall(P.SharedDataLine)
  local orb=pcall(P.OrbHubLine) and P.OrbHubLine() or 'raised'
  Nexus.StartupStatus=status
  return ok and text or ('raised: '..tostring(text)),orb
 end
 local shared={
  {{state='ready',coreReady=true},'+ Ready: shared builds and records'},
  {{state='pending',coreReady=true},'... Loading: shared builds and records; your Wishlists work now'},
  {{state='pending',coreReady=false},'... Loading: shared builds and records; Wishlist tools unlock after saved data is checked'},
  {{state='failed',coreReady=true},'! Unavailable: shared builds and records (see /nexus status)'},
  {function() error('synthetic status failure') end,'? Unknown: shared builds and records'},
 }
 for index,case in ipairs(shared) do
  local got=Shared(case[1])
  C.expect(got==case[2],'V5: shared case '..index..' reads '..case[2],got)
 end
 local _,orb=Shared({state='pending',coreReady=false})
 C.expect(orb=='? Unknown: the Orb run is not read yet','V5: before local readiness the Orb run is unknown, not "none"',orb)
end)

C.scenario('V6 Help names the footer routes it describes',function()
 local function Body(id) Nexus.Help.Show(id);return V.Plain(NexusHelpWindow.body:GetText() or '') end
 local sharing,orbs,troubleshooting=Body('sharing'),Body('orbs'),Body('troubleshooting')
 NexusHelpWindow:Hide()
 C.expect(sharing:find('Click Explore on the Nexus panel, then Build Library.',1,true)~=nil,'V6: Help sends Build Library readers to Explore')
 C.expect(orbs:find('Open /nexus orbs, Orbs on the Nexus panel, Orbs / Lost Memories in the ... menu',1,true)~=nil,
  'V6: Help lists the footer Orbs route beside the kept ones')
 C.expect(troubleshooting:find('Explore',1,true)~=nil and troubleshooting:find('loading or unavailable',1,true)~=nil
   and not troubleshooting:find('Gray Build Library/Leaderboard tabs',1,true),
  'V6: troubleshooting names the current control and allows loading or failed startup',troubleshooting)
end)

C.scenario('V7 the prepared support report states the save boundary and who acts on it',function()
 local notice=Nexus.SupportReport.WrittenNotice({id='synthetic'})
 C.guard(notice:find('is prepared in memory',1,true)~=nil and notice:find('not yet verified on disk',1,true)~=nil,
  'V7: the notice still says prepared in memory, not verified on disk',notice)
 C.expect(notice:find('Nexus does not reload or log out for you.',1,true)~=nil,'V7: and that Nexus never reloads or logs out itself',notice)
end)

C.guard(#H.actions==bootActions and Nexus.RecomputeStats().autoEnabled~=true,'no game action after boot, and Auto stays OFF',
 #H.actions-bootActions)
C.finish('(status vocabulary, grouped menu with kept labels, footer hubs as navigation only; native NOT RUN)')
