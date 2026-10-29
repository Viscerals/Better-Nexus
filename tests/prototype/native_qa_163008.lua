-- Native QA on installed test.163008 (the testers' screenshots were not
-- pixel-inspected in this runner; every check here is offline).
-- N1 Help in each Nexus window opens the guided setup coach (design/current
--    "Nexus Setup Alternative": Help opens the coach, the manual is Reference
--    on request); a separately labelled Reference opens that window's own
--    manual page. While an Auto warning waits, the coach refuses and says
--    why; Help then opens nothing else and the window stays for a retry
--    (composition review: Help never chooses the manual by itself). The
--    Records (Leaderboard) Help no longer opens the seven-page manual. The
--    manual keeps its privacy and consent warnings.
-- N2 The Options menu offers every established route as a direct choice (no
--    single Manage submenu), with Appearance, opened at the Options button;
--    Help text names those direct paths. No stock row cap or client minimum
--    height is claimed (the dropdown export grows its rows); native fit is
--    NOT_RUN.
-- N3 Hide details collapses the Play panel's detail section (the four counts
--    and the names behind them) and its space; Show details restores them
--    with the same counts; a reload starts collapsed with the same counts.
--    Nothing is saved, sent or acted on.
-- N4 The Plan editor's Display Settings popup no longer covers the editor's
--    upper-right control band (Import / Export, My Builds, the locked Echo
--    slots and their Auto-manage checkbox, Plan alternatives); its own
--    controls stay inside it and above it, at scaled and edge layouts.
-- Categories (view_regression_support): EXPECT is behaviour added by this
-- correction (predicted from source to fail at 0e5b84d7: the window Help
-- buttons call Help.Show, the menu nests Manage, Details keeps the counts,
-- the popup anchors under its button; not executed by the author). GUARD is
-- navigation-only, no-write behaviour that already held. SETUP is the
-- fixture. Geometry is the harness anchor model (layout_geometry_support),
-- not native glyphs, scale or hit testing: native NOT_RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('native_qa_163008')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local function Effects()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'saved='..F.Serialize(NexusDB),
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
-- Without the saved root: reopening a window may keep its own view state.
local function NavEffects()
 local s=Nexus.SyncModePolicy and Nexus.SyncModePolicy.Mode and Nexus.SyncModePolicy.Mode() or '?'
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'sync='..tostring(s),
  'settings='..F.Serialize(NexusDB.settings or {}),'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
-- Counts calls of owner[key] while body runs; the stand-in returns true and
-- opens nothing. Restored at once, also when body raises.
local function Spy(owner,key,body)
 local real=owner[key]
 local spy={n=0}
 owner[key]=function(...) spy.n=spy.n+1;spy.args={...};return true end
 local ok,err=pcall(body)
 owner[key]=real
 assert(ok,err)
 return spy
end
-- The coach and the manual boundaries around one click.
local function Routes(click)
 local manual
 local coach=Spy(Nexus.GuidedSetupUI,'Show',function()
  manual=Spy(Nexus.Help,'Show',click)
 end)
 return coach,manual
end
-- The coach refusing as while an Auto warning waits for its answer.
local function Refusing(body)
 local ui=Nexus.GuidedSetupUI
 local real=ui.Show
 ui.Show=function() return false,'warning-open' end
 local ok,err=pcall(body)
 ui.Show=real
 assert(ok,err)
end
-- What was printed (chat) while fn ran, plain.
local function Heard(fn)
 local heard,realPrint={},print
 print=function(...) heard[#heard+1]=tostring((...)) end
 local ok,err=pcall(fn)
 print=realPrint
 assert(ok,err)
 return V.Plain(table.concat(heard,' / '))
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
C.setup(not Nexus.OverwriteWarning.IsOpen(),'fixture: no Auto warning waits')
Nexus.DisableOrdinaryAutomation()

-- Each window family: how to open it, its Help and Reference buttons, and the
-- manual page its Reference names.
local WINDOWS={
 {name='Build Library',page='sharing',open=function() Nexus.CommunityBuilds.Show();return NexusCommunityBuildsFrame end,
  buttons=function(f) return f._helpNav,f._referenceNav end},
 {name='Records (Leaderboard)',page='sharing',open=function() Nexus.Leaderboard.Show();return NexusLeaderboardFrame end,
  buttons=function(f) return f._helpNav,f._referenceNav end},
 {name='Plan (Wishlist Editor)',page='wishlists',open=function() Nexus.WishlistEditor.Show();return NexusEditorFrame end,
  buttons=function(f) return f._helpNav,f._referenceNav end},
 {name='Orbs',page='orbs',open=function() return Nexus.OrbPanel.Show() end,
  buttons=function(f) return V.Button(H,f,'Help'),V.Button(H,f,'Reference') end},
}
local function Close(w)
 for _,name in ipairs({'NexusCommunityBuildsFrame','NexusLeaderboardFrame','NexusEditorFrame','NexusOrbPanel'}) do
  local f=_G[name];if f and f:IsShown() then f:Hide() end
 end
 if _G.NexusHelpWindow then NexusHelpWindow:Hide() end
 if Nexus.GuidedSetupUI then Nexus.GuidedSetupUI.Hide() end
end

for i,w in ipairs(WINDOWS) do
 C.scenario('N1.'..i..' '..w.name..': Help opens the coach; Reference opens the '..w.page..' page',function()
  Close()
  local f=w.open()
  if not C.setup(f~=nil and f:IsShown(),'N1.'..i..': fixture: the '..w.name..' window is open') then return end
  local help,reference=w.buttons(f)
  C.expect(help~=nil and V.Plain(help:GetText())=='Help' and help:IsShown(),'N1.'..i..': the window offers Help')
  C.expect(reference~=nil and V.Plain(reference:GetText())=='Reference' and reference:IsShown(),
   'N1.'..i..': the window offers the manual under its own label, Reference')
  if not (help and reference) then return end
  local before=NavEffects()
  local coach,manual=Routes(function() help:Click() end)
  C.expect(coach.n==1 and manual.n==0,'N1.'..i..': Help opens the guided setup coach (GuidedSetupUI.Show), not the manual (Help.Show)',
   'coach='..coach.n..' manual='..manual.n)
  Close();f=w.open();help,reference=w.buttons(f)
  coach,manual=Routes(function() reference:Click() end)
  C.expect(manual.n==1 and manual.args[1]==w.page and coach.n==0,
   'N1.'..i..': Reference opens the manual at the window\'s own page and not the coach',
   'manual='..manual.n..' page='..tostring(manual.args and manual.args[1])..' coach='..coach.n)
  Close();f=w.open();help,reference=w.buttons(f)
  -- Composition review item 4: a refused coach never makes Help choose the
  -- manual. It says why; the calling window stays (with whatever it holds)
  -- and pressing Help again once the coach can open opens it.
  local fallback,said
  Refusing(function() said=Heard(function() fallback=Spy(Nexus.Help,'Show',function() help:Click() end) end) end)
  C.expect(fallback.n==0 and f:IsShown() and said:find('Answer the open warning',1,true)~=nil,
   'N1.'..i..': while an Auto warning waits, Help says why, opens no Reference page and the window stays',
   'reference='..fallback.n..' shown='..tostring(f:IsShown())..' said='..said)
  coach,manual=Routes(function() help:Click() end)
  C.expect(coach.n==1 and manual.n==0,'N1.'..i..': Help again opens the coach once it can','coach='..coach.n..' manual='..manual.n)
  Close()
  C.guard(NavEffects()==before,'N1.'..i..': Help and Reference only navigate: no action, send, setting or Auto change',NavEffects())
 end)
end

C.scenario('N1.5 the manual keeps its privacy and consent warnings; the Automation menu link is Reference',function()
 local pages={}
 for _,p in ipairs(Nexus.Help.Pages) do pages[p.id]=p.text end
 for _,s in ipairs({'asks you to confirm first','Sending is not delivery','A shared build cannot be recalled',
  'What Sync sends: your saved Sync mode decides','Sync is Off: Nexus sends nothing'}) do
  C.guard((pages.sharing or ''):find(s,1,true)~=nil,'N1.5: the Sharing page keeps: '..s)
 end
 C.guard((pages.troubleshooting or ''):find('never post it publicly',1,true)~=nil,'N1.5: the support page keeps the private-file warning')
 Nexus.Help.Show('sharing')
 C.expect(V.Plain(NexusHelpWindow.title:GetText() or '')=='Nexus Reference - Shared builds and DPS',
  'N1.5: the manual window is titled Reference, not Help',NexusHelpWindow.title:GetText())
 NexusHelpWindow:Hide()
 local rows=Nexus.Readout.AutomationSettingsRows({})
 local link=rows[#rows]
 C.expect(link and link.kind=='help' and link.text=='What Auto may do (Reference)...',
  'N1.5: the Automation settings link to the manual says Reference',link and link.text)
end)

-- A build in progress for the Play panel (synthetic).
local function Model()
 return {status='ready',level=40,auto=false,cards={},recommendation='',
  progress={wishlistName='Synthetic QA plan',total=6,owned=2,missing={'Cinder Lattice x2 (Rare:x2)','Hollow Bell'},
   shed={'Ashen Tithe'},toLock={'Gravecall Chorus'},unknownTomes={'Frostwake Sigil'}}}
end

-- N2 the Options menu as EasyMenu receives it at the Options button.
local function OpenOptions()
 local captured
 local easy,close=EasyMenu,CloseDropDownMenus
 EasyMenu=function(list,menuFrame,anchor) captured={list=list,frame=menuFrame,anchor=anchor} end
 CloseDropDownMenus=function() end
 local ok,err=pcall(function() NexusPanel._menuBtn:GetScript('OnClick')(NexusPanel._menuBtn) end)
 EasyMenu,CloseDropDownMenus=easy,close
 assert(ok,err)
 return captured
end
local function Item(items,text)
 for _,item in ipairs(items or {}) do if item.text==text then return item end end
end
local function Prefixed(items,prefix)
 for _,item in ipairs(items or {}) do
  if type(item.text)=='string' and item.text:sub(1,#prefix)==prefix then return item end
 end
end

C.scenario('N2 Options offers every route directly, with Appearance, inside the dropdown limits',function()
 Close()
 Nexus.Panel.Show()
 C.setup(Nexus.Panel.Render(Model())==true and NexusPanel and NexusPanel._menuBtn,'N2: fixture: the panel renders with its Options button')
 local before=Effects()
 local opened=OpenOptions()
 if not C.setup(opened~=nil and type(opened.list)=='table','N2: fixture: the Options button opens its menu') then return end
 local top=opened.list
 C.expect(opened.anchor==NexusPanel._menuBtn,'N2: the menu opens at the Options button')
 C.expect(Item(top,'Manage')==nil,'N2: there is no single Manage submenu')
 local missing={}
 for _,label in ipairs({'Help / Getting Started','Reference (full manual)','Setup / Welcome','Setup information (read only)',
  'Setup checklist and status','Support report...','Open Settings...','Log viewer...','Orbs / Lost Memories',
  'Wishlist Editor','Reset Panel Position','Hide Nexus Panel'}) do
  local item=Item(top,label)
  if not (item and type(item.func)=='function') then missing[#missing+1]=label end
 end
 for _,prefix in ipairs({'Appearance: ','Automation settings','Language'}) do
  local item=Prefixed(top,prefix)
  if not (item and item.hasArrow and type(item.menuList)=='table' and #item.menuList>0) then missing[#missing+1]=prefix..'>' end
 end
 if not (Item(top,'Show DPS records') or Item(top,'Hide DPS records')) then missing[#missing+1]='DPS records' end
 if not (Item(top,'Use Server Difficulty / Soul Ash HUD') or Item(top,'Use Nexus Difficulty / Soul Ash HUD')) then
  missing[#missing+1]='HUD mode'
 end
 if not (Item(top,'Disable Update Notices') or Item(top,'Enable Update Notices')) then missing[#missing+1]='Update Notices' end
 if not Prefixed(top,'Update notices: ') then missing[#missing+1]='Update notices: *' end
 C.expect(#missing==0,'N2: every action is a direct choice (Appearance, Automation settings and Language keep their lists)',
  table.concat(missing,', '))
 -- Issue #170 added the Main panel size list (its sizes and Reset to 100%).
 local submenus={}
 for _,item in ipairs(top) do
  if item.hasArrow then
   local name=tostring(item.text)
   for _,prefix in ipairs({'Appearance: ','Automation settings','Language','Main panel size: '}) do
    if name:sub(1,#prefix)==prefix then name=prefix end
   end
   submenus[#submenus+1]=name
  end
 end
 table.sort(submenus)
 C.expect(table.concat(submenus,'|')=='Appearance: |Automation settings|Language|Main panel size: ',
  'N2: only Appearance, Automation settings, Language and Main panel size open a list',table.concat(submenus,'|'))
 -- No stock row cap is claimed: the 3.3.5a UIDropDownMenu export starts at 8
 -- buttons per level and grows them per added item (build 12340, L1-5 and
 -- L178-229). The synthetic height below (16-unit rows plus a 32-unit
 -- border) is recorded, not judged against any client minimum: whether the
 -- menu fits the screen at a UI scale is native NOT_RUN.
 print('OBSERVED','N2 synthetic menu height',#top..' rows',#top*16+32)
 local unlabelled=0
 for _,item in ipairs(top) do if not (type(item.text)=='string' and item.text~='') then unlabelled=unlabelled+1 end end
 C.expect(#top>0 and unlabelled==0,'N2: every top-level row has a label',unlabelled)
 C.guard(Effects()==before,'N2: opening the menu changes nothing',Effects())
 -- Help is the coach; Reference is the manual's first page.
 local coach,manual=Routes(function() Item(top,'Help / Getting Started').func() end)
 C.expect(coach.n==1 and manual.n==0,'N2: Help / Getting Started opens the coach','coach='..coach.n..' manual='..manual.n)
 coach,manual=Routes(function() Item(top,'Reference (full manual)').func() end)
 C.expect(manual.n==1 and manual.args[1]=='start' and coach.n==0,'N2: Reference (full manual) opens the manual','manual='..manual.n)
 Close()
 C.guard(Effects()==before,'N2: Help and Reference change nothing',Effects())
end)

C.scenario('N2.1 Help, chat and hover text name the direct Options paths the menu has',function()
 local all=''
 for _,p in ipairs(Nexus.Help.Pages) do all=all..p.text..'\n' end
 C.expect(not all:find('Manage',1,true),'N2.1: no manual page describes the retired Manage submenu')
 local top=OpenOptions().list
 for _,pair in ipairs({{'(Options > Setup / Welcome)','Setup / Welcome'},{'Options > Automation settings','Automation settings'},
  {'Hide Nexus Panel (Options)','Hide Nexus Panel'},{'Orbs / Lost Memories in the Options menu','Orbs / Lost Memories'}}) do
  C.expect(all:find(pair[1],1,true)~=nil and (Item(top,pair[2]) or Prefixed(top,pair[2]))~=nil,
   'N2.1: the manual names "'..pair[1]..'" and the menu has '..pair[2])
 end
 local chat=Nexus.UserText.Guide and Nexus.UserText.Guide.chat or {}
 for _,key in ipairs({'reopen','reopenSession'}) do
  local text=tostring(chat[key] or '')
  C.expect(text:find('Options menu: Setup / Welcome',1,true)~=nil and not text:find('Manage',1,true),
   'N2.1: the coach\'s '..key..' chat line names the direct Options entry',text)
 end
 C.expect(not tostring(Nexus.UserText.GLOSSARY or ''):find('Manage',1,true),'N2.1: the glossary names no Manage submenu')
 Nexus.Panel.Show()
 local grip=NexusPanel._dragGrip
 if grip then
  local tip=table.concat(V.TooltipLines(grip:GetScript('OnEnter'),grip),' ')
  C.expect(tip:find('Options > Reset Panel Position',1,true)~=nil and not tip:find('Manage',1,true),
   'N2.1: the grip hover names the direct Reset Panel Position entry',tip)
 end
end)

-- N3 the Play panel's detail section.
local function Counts(p)
 return table.concat({V.Plain(p.needed:GetText() or ''),V.Plain(p.tomes:GetText() or ''),
  V.Plain(p.extra:GetText() or ''),V.Plain(p.locked:GetText() or '')},' | ')
end
local function SectionShown(p)
 return p.needed:IsShown(),p.tomes:IsShown() and p.extra:IsShown() and p.locked:IsShown()
end
local function ShownText()
 local out={}
 for _,r in ipairs(G.Shown(NexusPanel)) do if r.kind=='FontString' then out[#out+1]=V.Plain(r:GetText() or '') end end
 return table.concat(out,' | ')
end
local COUNTS='Still needed  4 copies | Missing tomes  1 Echo | Extra copies  1 listed | Locked targets  1 to lock'

local savedCounts
C.scenario('N3 Hide details collapses the detail section and its space; Show details restores the same counts',function()
 Close()
 local P=Nexus.Panel
 P.Show()
 if not C.setup(P.Render(Model())==true and NexusPanel._play~=nil,'N3: fixture: the Play panel renders a build in progress') then return end
 local p=NexusPanel._play
 local before=Effects()
 local collapsedH=NexusPanel:GetHeight()
 local one=SectionShown(p)
 C.expect(not one and V.Plain(p.details:GetText())=='Show details','N3: the detail section starts collapsed; the button says Show details')
 C.expect(Counts(p)==COUNTS,'N3: the counts are worded while collapsed',Counts(p))
 p.details:Click()
 C.setup(P.Render(Model())==true,'N3: fixture: the same model rendered again')
 local a,b=SectionShown(p)
 local text=ShownText()
 C.expect(a and b and text:find('Hollow Bell',1,true)~=nil and V.Plain(p.details:GetText())=='Hide details',
  'N3: Show details shows the four counts and the names behind them',text)
 local openH=NexusPanel:GetHeight()
 C.expect(openH>collapsedH and openH==NexusPanel._responsiveLayout.height,'N3: the panel grows by the section',collapsedH..' -> '..openH)
 savedCounts=Counts(p)
 C.expect(savedCounts==COUNTS,'N3: the shown counts are the plan\'s counts',savedCounts)
 p.details:Click()
 P.Render(Model())
 a=SectionShown(p)
 text=ShownText()
 C.expect(not a and not text:find('Still needed',1,true) and not text:find('Missing tomes',1,true)
  and not text:find('Hollow Bell',1,true),'N3: Hide details collapses the Still needed / Missing tomes section',text)
 C.expect(NexusPanel:GetHeight()==collapsedH and NexusPanel._responsiveLayout.boxes.planNeeded==nil,
  'N3: Hide details gives back the section\'s whole space',NexusPanel:GetHeight())
 p.details:Click();P.Render(Model())
 C.expect(Counts(p)==savedCounts and NexusPanel:GetHeight()==openH,'N3: Show details again restores the same counts and space',Counts(p))
 p.details:Click();P.Render(Model())
 C.guard(Effects()==before,'N3: hiding and showing details saves, sends and acts on nothing and leaves Auto as it was',Effects())
end)

C.scenario('N3.1 after a reload the section starts collapsed and Show details gives the same counts',function()
 -- An offline module reload with the saved data round-tripped (F.Reload),
 -- not a client /reload.
 H=F.Reload(function(h) F.OrbService(h) end)
 C.setup(Nexus.StartupStatus().coreReady==true,'N3.1: fixture: the reloaded addon is ready')
 Nexus.DisableOrdinaryAutomation()
 local P=Nexus.Panel
 P.Show()
 if not C.setup(P.Render(Model())==true and NexusPanel._play~=nil,'N3.1: fixture: the reloaded panel renders') then return end
 local p=NexusPanel._play
 C.expect(P._playDetails~=true and not SectionShown(p) and V.Plain(p.details:GetText())=='Show details',
  'N3.1: details are memory only: a reload starts collapsed')
 p.details:Click();P.Render(Model())
 C.expect(SectionShown(p) and Counts(p)==(savedCounts or COUNTS),'N3.1: Show details after the reload gives the same counts',Counts(p))
 p.details:Click();P.Render(Model())
end)

-- N4 the Display Settings popup.
local function Band(f)
 local band={}
 local function Add(label,w) if w and w:IsShown() then band[#band+1]={label,w} end end
 for _,label in ipairs({'Import','Export','My Builds (game)','Plan alternatives','Display Settings'}) do
  Add(label,V.Button(H,f,label))
 end
 for _,c in ipairs(f.children or {}) do
  local pt=c.points and c.points[1]
  -- The Auto-manage checkbox sits right of the last locked slot icon.
  if c.kind=='CheckButton' and pt and type(pt[2])=='table' and pt[2].kind=='Button' then Add('the Auto-manage locked Echo slots checkbox',c) end
 end
 for i=1,8 do
  local ok,icon=pcall(function() return f._nexusLockedSlot and f._nexusLockedSlot(i) end)
  if ok and icon then band[#band+1]={'locked slot '..i,icon} end
 end
 return band
end

C.scenario('N4 Display Settings opens clear of the editor\'s upper-right controls; its own controls stay inside it',function()
 Close()
 local oldW,oldH=UIParent:GetWidth(),UIParent:GetHeight()
 UIParent:SetSize(1024,768)
 local ok,err=pcall(function()
  Nexus.WishlistEditor.Show()
  local f=NexusEditorFrame
  if not C.setup(f~=nil and f:IsShown(),'N4: fixture: the Plan editor is open') then return end
  local display=V.Button(H,f,'Display Settings')
  if not C.setup(display~=nil,'N4: fixture: the Display Settings button') then return end
  local before=Effects()
  display:Click()
  local p=_G.NexusDisplayPopup
  if not C.setup(p~=nil and p:IsShown(),'N4: fixture: the popup opens') then return end
  C.guard(p:GetFrameStrata()=='TOOLTIP','N4: the popup stays above the editor\'s HIGH layer')
  C.expect(p._nexusPlacement=='inside','N4: on a 1024-wide UI the popup opens inside the editor',p._nexusPlacement)
  local pr=G.Rect(p,f)
  print('OBSERVED','N4 popup',G.Text(pr))
  local band=Band(f)
  C.setup(#band>=10,'N4: fixture: the band controls are found',#band)
  for _,entry in ipairs(band) do
   local r=G.Rect(entry[2],f)
   C.expect(G.Apart(pr,r),'N4: the popup leaves '..entry[1]..' uncovered and clickable',G.Text(pr)..' / '..G.Text(r))
  end
  C.expect(G.Inside(pr,G.Rect(f,f)),'N4: the popup lies inside the editor',G.Text(pr))
  -- Unsized labels take their text width in the client; the harness gives
  -- every FontString a 100 px default box. Model the two the row anchors to.
  for _,r in ipairs(p.regions or {}) do
   local s=r.kind=='FontString' and V.Plain(r:GetText() or '') or ''
   if s=='Position' or s=='Size' then r:SetWidth(G.Length(s)*7) end
  end
  local level=p:GetFrameLevel()
  local inside,above,controls=true,true,0
  for _,c in ipairs(p.children or {}) do
   if c.kind=='Button' or c.kind=='CheckButton' or c.kind=='Slider' then
    controls=controls+1
    local cr=G.Rect(c,p)
    if c.kind=='Button' and V.Plain(c:GetText() or '')=='X' then
     if not G.Inside(cr,{0,0,p:GetWidth(),p:GetHeight()}) then inside=false end
    elseif not G.Inside(cr,{8,8,p:GetWidth()-8,p:GetHeight()-8}) then inside=false end
    if c:GetFrameLevel()<=level then above=false end
   end
  end
  C.expect(controls>=6 and inside,'N4: the popup\'s checkbox, buttons and slider lie inside it',controls)
  C.expect(above,'N4: each popup control is above the popup\'s own backdrop (receives its clicks)')
  display:Click()
  C.expect(not p:IsShown(),'N4: Display Settings still toggles the popup closed')
  C.guard(Effects()==before,'N4: opening and closing the popup changes nothing',Effects())
  f:Hide()
 end)
 UIParent:SetSize(oldW,oldH)
 assert(ok,err)
end)

C.scenario('N4.1 the popup placement at scaled and edge layouts stays on screen and off the band',function()
 local place=Nexus.WishlistEditor.DisplayPopupPlacement
 local BAND,W,PH=182,300,300 -- band bottom (editor units), popup width, a tall popup (large text)
 local cases={
  {name='16:9 at scale 1, centred',screenW=1365,left=162,width=1040,ratio=1,want='inside'},
  {name='4:3, FitToScreen 0.96',screenW=1024,left=13,width=1040,ratio=0.96,want='inside'},
  {name='5:4, FitToScreen 0.9',screenW=960,left=12,width=1040,ratio=0.9,want='inside'},
  {name='ultrawide, centred',screenW=1820,left=390,width=1040,ratio=1,want='right'},
  {name='ultrawide, at the right edge',screenW=1820,left=780,width=1040,ratio=1,want='left'},
  {name='small UI scale, at the left edge',screenW=2133,left=0,width=1040,ratio=1,want='right'},
 }
 for _,case in ipairs(cases) do
  for _,edge in ipairs({'top','bottom'}) do
   local h=680*case.ratio
   local top=edge=='top' and 768 or h
   local e={left=case.left,right=case.left+case.width*case.ratio,top=top,bottom=top-h}
   local r=place({editor=e,ratio=case.ratio,screenW=case.screenW,width=W})
   local tag='N4.1 '..case.name..', editor at the '..edge
   C.expect(r.where==case.want,tag..': opens '..case.want,r.where)
   -- The popup's screen rectangle (y up) from its anchor on the editor.
   local ax=r.relativePoint:find('RIGHT') and e.right or e.left
   local x1=r.point:find('RIGHT') and ax+r.x-W or ax+r.x
   local y1=e.top+r.y
   local popup={x1,y1-PH,x1+W,y1}
   C.expect(popup[1]>=0 and popup[3]<=case.screenW and popup[2]>=0 and popup[4]<=768,
    tag..': the whole popup is on screen without clamping',string.format('%.0f,%.0f-%.0f,%.0f',popup[1],popup[2],popup[3],popup[4]))
   if r.where=='inside' then
    C.expect(popup[4]<=e.top-BAND*case.ratio+0.001 and popup[1]>=e.left and popup[3]<=e.right,
     tag..': inside, its top is at or below the band and it stays within the editor\'s width')
   else
    C.expect(popup[3]<=e.left or popup[1]>=e.right,tag..': beside, it covers no part of the editor')
   end
  end
 end
end)

C.guard(#H.actions==0,'no game action anywhere in this test',#H.actions)
C.finish('(window Help opens the coach, Reference the manual; direct Options; collapsible details; popup clear of the band; offline model only, native NOT_RUN)')
