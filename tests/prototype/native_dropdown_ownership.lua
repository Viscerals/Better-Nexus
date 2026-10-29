-- Nexus-owned native menus after native acceptance of test.163009: the
-- Options menu fitted the screen, but main-panel text stayed readable through
-- it. EasyMenu initializes the Nexus anchor frame and then displays the menu
-- in the shared DropDownList<n> frames that every game and addon menu reuses,
-- so nothing Nexus styled was on screen. Theme.OpenMenu now gives the shared
-- list that shows a Nexus menu one opaque fill, only while that list is shown
-- and the root menu open in it (UIDROPDOWNMENU_OPEN_MENU) is an initializer a
-- Nexus menu opened.
-- M0 before any Nexus menu, a stock menu gets no texture and no hook;
-- M1 the actual Options button: one EasyMenu call as before, every item its
--    own row with its own handler (rows past the first eight made on demand,
--    no cap), and DropDownList1 gets one opaque BACKGROUND fill of its own,
--    over the stock MenuBackdrop's background area and under every row, with
--    the list's stock surface, size, anchors, strata and level unchanged;
-- M2 its submenus (Appearance, Language) reuse DropDownList2 with the same
--    root identity: filled while shown, unfilled when a plain row closes it;
-- M3 a dynamically created third level, the stock row click (handler and its
--    arguments, checked state), tooltip ownership through the stock row hover,
--    a close while the open-menu global still names the Nexus menu, reopen
--    without a second texture or hook, and the stock same-owner toggle;
-- M4 another addon's and a game menu reusing the same lists (while the Nexus
--    menu and its submenu were shown): no fill, their own surface, rows,
--    handlers and tooltip, then the Nexus menu again is filled again;
-- M5 the Appearance menu (Theme.ShowMenu) and the Plan hub menu route through
--    the same owner;
-- M6 a level only another addon ever showed stays stock;
-- M7 (issue #165) the actual Options button toggles: a second click while its
--    menu is shown leaves it closed (also from an open submenu), a later click
--    opens it again; after a stock close or a timeout hide, another Nexus menu
--    or another addon's menu, one click opens Options normally.
-- M8 (native test.163012) ordinary HUD renders before and after every
--    Options click keep closed -> open -> closed -> open with one EasyMenu
--    per opening, an open submenu and its fills, and a foreign menu that
--    reused the list after Options (shown and unfilled through a render);
-- M9 (native test.163012) Pause and Resume through the stock row click: the
--    row's list hides before its callback, the real owner runs once, the
--    title changes at once, and reopened Options offers the other choice.
--    M8 and M9 are GUARD: they already held at b1ef408, so the native
--    Resume failure is not reproduced by the stock dispatch modelled here.
-- The dropdown below is a synthetic stand-in written from the verified
-- build-3.3.5.12340 export facts (DROPDOWN_LIFECYCLE_CONTRACT: UIDropDownMenu
-- .lua 35-69, 178-229, 539-563, 576-789 and 794-810; UIDropDownMenu.xml 5-20;
-- UIDropDownMenuTemplates.xml 130-150, 163-196 and 219-235; EasyMenu.lua
-- 17-22): shared lists and rows made on demand, level-1 open identity that
-- submenus keep, an initializer that hides another owner's list, a hide before
-- every redraw, MENU / dropdown backdrops, placement after Show, the hide
-- cascade, an open-menu global that outlives the display, and the row click
-- and hover routes. The tooltip owner of a row hover is modelled as the row
-- (GameTooltip_AddNewbieTip's final owner is not verified). It is not the
-- client's code: effective opacity, inherited alpha, draw order, hit testing
-- and any other addon's overrides are native NOT_RUN. Categories
-- (view_regression_support): EXPECT is behaviour added by this correction
-- (predicted from source to fail at a9ff2eda: no fill exists; not executed by
-- the author), GUARD already held and must keep holding, SETUP is the fixture.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('native_dropdown_ownership')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local P,T=Nexus.Panel,Nexus.Theme
local function Effects()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'saved='..F.Serialize(NexusDB),
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
local function Model()
 return {status='ready',level=40,auto=false,cards={},recommendation='',
  progress={wishlistName='Synthetic menu plan',total=6,owned=2,missing={'Cinder Lattice x2 (Rare:x2)','Hollow Bell'},
   shed={'Ashen Tithe'},toLock={'Gravecall Chorus'},unknownTomes={'Frostwake Sigil'}}}
end

-- Observation only: the harness keeps no draw layer or vertex colour. Each
-- texture records the layer it was created in and its last vertex colour.
local RM=G.RegionMethods()
do
 local create=rawget(RM,'CreateTexture')
 RM.CreateTexture=function(self,name,layer,...)
  local t=create(self,name,layer,...)
  t._layer=layer
  return t
 end
 RM.SetVertexColor=function(self,r,g,b,a) self._vertex={r,g,b,a==nil and 1 or a} end
end

------------------------------------------------------------------------
-- Synthetic FrameXML dropdown (see the header)
------------------------------------------------------------------------
local D={levels=0,maxButtons=8,placed={},easy={},stock={shows=0,hides=0}}
local ROW_H=16
local function ListName(level) return 'DropDownList'..level end
local function Points(r)
 local out={}
 for i,p in ipairs(r.points) do
  local t={}
  for j=1,5 do t[j]=tostring(p[j]) end
  out[i]=table.concat(t,',')
 end
 return table.concat(out,';')
end
-- UIDropDownMenuTemplates.xml 219-231: size from rows, show time, and the
-- logical previous-level parent above level one.
function D.ListOnShow(self)
 D.stock.shows=D.stock.shows+1
 local id=self:GetID()
 if id>1 then self.parent=_G[ListName(id-1)] end
 self.showTime=H.now
end
-- UIDropDownMenu_OnHide, Lua 803-810: the stored onHide, then the higher levels.
function D.ListOnHide(self)
 D.stock.hides=D.stock.hides+1
 local id=self:GetID()
 if self.onHide then self.onHide(id+1);self.onHide=nil end
 CloseDropDownMenus(id+1)
end
-- Lua 539-563: the row's list hides unless keepShownOnClick, then the
-- callback runs with (row, arg1, arg2, checked).
function D.RowOnClick(self)
 local checked=self.checked
 if not self.keepShownOnClick then self:GetParent():Hide() end
 if self.func then self.func(self,self.arg1,self.arg2,checked) end
end
-- UIDropDownMenuTemplates.xml 130-150: an arrow opens the next level from
-- this row, any other row closes the levels above; a tooltip title is shown.
function D.RowOnEnter(self)
 local level=self:GetParent():GetID()
 if self.hasArrow then
  ToggleDropDownMenu(level+1,self.value,nil,nil,nil,nil,self.menuList,self)
 else
  CloseDropDownMenus(level+1)
 end
 if self.tooltipTitle then
  GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
  GameTooltip:AddLine(self.tooltipTitle)
  GameTooltip:Show()
 end
end
local function NewRow(list,index)
 local row=CreateFrame('Button',list:GetName()..'Button'..index,list)
 row:Hide()
 row:SetScript('OnClick',D.RowOnClick)
 row:SetScript('OnEnter',D.RowOnEnter)
 return row
end
local function NewList(level)
 local name=ListName(level)
 local list=CreateFrame('Button',name,UIParent)
 list:Hide()
 list.GetID=function() return level end
 list:SetFrameStrata('FULLSCREEN_DIALOG')
 for _,suffix in ipairs({'Backdrop','MenuBackdrop'}) do
  local b=CreateFrame('Frame',name..suffix,list)
  b:SetPoint('TOPLEFT',list,'TOPLEFT',0,0)
  b:SetPoint('BOTTOMRIGHT',list,'BOTTOMRIGHT',0,0)
  b:Hide()
 end
 list:SetScript('OnShow',D.ListOnShow)
 list:SetScript('OnHide',D.ListOnHide)
 for index=1,D.maxButtons do NewRow(list,index) end
 return list
end
-- Lua 178-201: levels and rows grow on demand, across every level.
function UIDropDownMenu_CreateFrames(level,index)
 while D.levels<level do D.levels=D.levels+1;NewList(D.levels) end
 if index>D.maxButtons then
  for l=1,D.levels do for i=D.maxButtons+1,index do NewRow(_G[ListName(l)],i) end end
  D.maxButtons=index
 end
end
local ROW_FIELDS={'text','value','func','arg1','arg2','checked','hasArrow','menuList','owner',
 'tooltipTitle','keepShownOnClick','notCheckable','isTitle','disabled'}
-- Lua 215-329: the next row of the level, with the item's fields copied.
function UIDropDownMenu_AddButton(info,level)
 level=level or 1
 local list=_G[ListName(level)]
 local index=(list.numButtons or 0)+1
 UIDropDownMenu_CreateFrames(level,index)
 local row=_G[list:GetName()..'Button'..index]
 for _,k in ipairs(ROW_FIELDS) do row[k]=info[k] end
 row:SetText(info.text or '')
 row:Show()
 list.numButtons=index
end
local function ResetList(list)
 for i=1,D.maxButtons do
  local row=_G[list:GetName()..'Button'..i]
  if row then row:Hide() end
 end
 list.numButtons=0
end
-- Lua 35-69: another owner starts again at level one; every list at or above
-- the current menu level (every list, for another owner) is reset and
-- hidden, then the initializer is stored and called. The same owner at level
-- one is hidden too: EasyMenu (17-22) initializes before it toggles, so it
-- never reaches the same-owner toggle of an open root list (594-595).
UIDROPDOWNMENU_MENU_LEVEL=1
function UIDropDownMenu_Initialize(frame,init,displayMode,level,menuList)
 frame.menuList=menuList
 if frame~=UIDROPDOWNMENU_OPEN_MENU then UIDROPDOWNMENU_MENU_LEVEL=1 end
 for i=1,D.levels do
  local list=_G[ListName(i)]
  if list and (i>=UIDROPDOWNMENU_MENU_LEVEL or frame~=UIDROPDOWNMENU_OPEN_MENU) then ResetList(list);list:Hide() end
 end
 if init then frame.initialize=init;init(frame,level,frame.menuList) end
end
function EasyMenu_Initialize(frame,level,menuList)
 for _,info in ipairs(menuList or {}) do UIDropDownMenu_AddButton(info,level) end
end
-- Lua 576-789: a same-owner level-1 toggle hides; any other open hides the
-- list, records the level-1 owner (submenus keep it), redraws, picks the
-- backdrop for the display mode, shows, and only then places the list.
function ToggleDropDownMenu(level,value,dropDownFrame,anchorName,xOffset,yOffset,menuList,button)
 level=level or 1
 UIDropDownMenu_CreateFrames(level,0)
 UIDROPDOWNMENU_MENU_LEVEL,UIDROPDOWNMENU_MENU_VALUE=level,value
 local list=_G[ListName(level)]
 if not dropDownFrame then dropDownFrame=UIDROPDOWNMENU_OPEN_MENU end
 if level==1 and list:IsShown() and UIDROPDOWNMENU_OPEN_MENU==dropDownFrame then list:Hide();return end
 list:Hide()
 if level==1 then UIDROPDOWNMENU_OPEN_MENU=dropDownFrame end
 local name=list:GetName()
 local back,menu=_G[name..'Backdrop'],_G[name..'MenuBackdrop']
 if dropDownFrame and dropDownFrame.displayMode=='MENU' then back:Hide();menu:Show() else back:Show();menu:Hide() end
 -- Lua 714-715: the level is initialized (reset, hidden and filled) again.
 UIDropDownMenu_Initialize(dropDownFrame,dropDownFrame.initialize,nil,level,menuList)
 if (list.numButtons or 0)==0 then return end
 list:SetSize(180,list.numButtons*ROW_H+30)
 list:Show()
 list:ClearAllPoints()
 if level==1 then
  local anchor=(anchorName=='cursor' or anchorName==nil) and UIParent or anchorName
  list:SetPoint('TOPLEFT',anchor,'BOTTOMLEFT',xOffset or 0,yOffset or 0)
 else
  list:SetPoint('TOPLEFT',button or UIParent,'TOPRIGHT',0,0)
 end
 list.onHide=dropDownFrame and dropDownFrame.onHide
 D.placed[list]={w=list:GetWidth(),h=list:GetHeight(),points=Points(list),level=list:GetFrameLevel()}
end
-- Lua 794-800: every level from `level` up hides.
function CloseDropDownMenus(level)
 for i=level or 1,D.levels do
  local list=_G[ListName(i)]
  if list then list:Hide() end
 end
end
-- EasyMenu.lua 17-22, with each call recorded.
function EasyMenu(menuList,menuFrame,anchor,x,y,displayMode)
 D.easy[#D.easy+1]={list=menuList,frame=menuFrame,anchor=anchor,x=x,y=y,mode=displayMode}
 if displayMode=='MENU' then menuFrame.displayMode=displayMode end
 UIDropDownMenu_Initialize(menuFrame,EasyMenu_Initialize,displayMode,nil,menuList)
 ToggleDropDownMenu(1,nil,menuFrame,anchor,x,y,menuList,nil)
end
UIDROPDOWNMENU_OPEN_MENU=nil
UIDropDownMenu_CreateFrames(2,0)

------------------------------------------------------------------------
-- Reads
------------------------------------------------------------------------
local WHITE='Interface\\Buttons\\WHITE8X8'
local STRATA={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
local function List(level) return _G[ListName(level)] end
local function Fills(list)
 local out={}
 for _,r in ipairs(list and list.regions or {}) do
  if r.kind=='Texture' and r.texture==WHITE then out[#out+1]=r end
 end
 return out
end
local function Fill(list) local f=Fills(list);return f[1],#f end
local function FillShown(level) local f=Fill(List(level));return f~=nil and f:IsShown() end
-- The shown row of a level whose label starts with `text`.
local function Row(level,text)
 local list=List(level)
 for i=1,(list and list.numButtons or 0) do
  local row=_G[list:GetName()..'Button'..i]
  if row and row:IsShown() and V.Plain(row:GetText() or ''):sub(1,#text)==text then return row end
 end
end
local function FirstPlainRow(level)
 local list=List(level)
 for i=1,(list and list.numButtons or 0) do
  local row=_G[list:GetName()..'Button'..i]
  if row and row:IsShown() and not row.hasArrow then return row end
 end
end
-- Every item of `items` is the shown row of the same index on `level`, with
-- the same label, handler, arguments and submenu.
local function RowsMatch(level,items)
 local list=List(level)
 if not (list and list.numButtons==#items) then return false end
 for i,item in ipairs(items) do
  local row=_G[list:GetName()..'Button'..i]
  if not (row and row:IsShown() and row:GetParent()==list and row:GetText()==tostring(item.text or '')
   and row.func==item.func and row.arg1==item.arg1 and row.arg2==item.arg2
   and row.hasArrow==item.hasArrow and row.menuList==item.menuList) then return false end
 end
 return true
end
-- The fill of a shown Nexus list: one texture of the list itself, in its
-- BACKGROUND layer, over the stock MenuBackdrop's background area (its
-- 5-unit insets), in the active style's opaque base colour; the backdrop and
-- every row are child frames of the list, so they draw over it, and the list
-- keeps its FULLSCREEN_DIALOG strata, above the main panel.
local function Opaque(level,tag)
 local list=List(level)
 local fill,n=Fill(list)
 if not C.expect(fill~=nil and n==1 and fill:IsShown(),tag..': the shown list has exactly one Nexus fill, shown',n) then return end
 local surface=_G[list:GetName()..'MenuBackdrop']
 local a,b=fill.points[1],fill.points[2]
 C.expect(fill:GetParent()==list and fill._layer=='BACKGROUND' and #fill.points==2
  and a[1]=='TOPLEFT' and a[2]==surface and a[3]=='TOPLEFT' and a[4]==5 and a[5]==-5
  and b[1]=='BOTTOMRIGHT' and b[2]==surface and b[3]=='BOTTOMRIGHT' and b[4]==-5 and b[5]==5,
  tag..': the fill is the list\'s own BACKGROUND texture over its MenuBackdrop\'s background area',
  tostring(fill._layer)..' '..Points(fill))
 local want=T.STYLES[T.Current().style].baseColor
 local v=fill._vertex
 C.expect(v~=nil and v[4]==1 and v[1]==want[1] and v[2]==want[2] and v[3]==want[3],
  tag..': the fill is the active style\'s base colour at alpha 1',v and table.concat({v[1],v[2],v[3],v[4]},','))
 local rowsAbove=surface:GetParent()==list
 for i=1,list.numButtons or 0 do
  local row=_G[list:GetName()..'Button'..i]
  if row:IsShown() and row:GetParent()~=list then rowsAbove=false end
 end
 C.guard(rowsAbove and fill.kind=='Texture'
  and (STRATA[list:GetFrameStrata()] or 0)>(STRATA[NexusPanel:GetFrameStrata()] or STRATA.TOOLTIP),
  tag..': its backdrop and rows are child frames of the list (drawn over the fill, which takes no mouse); the list stays above the main panel',
  list:GetFrameStrata()..' / '..NexusPanel:GetFrameStrata())
end
-- The list keeps the stock surface of its display mode and the stock size,
-- anchors, strata and level ToggleDropDownMenu gave it.
local function Stock(level,mode,tag)
 local list=List(level)
 local name=list:GetName()
 local menu,back=_G[name..'MenuBackdrop'],_G[name..'Backdrop']
 C.guard(menu:IsShown()==(mode=='MENU') and back:IsShown()==(mode~='MENU'),
  tag..': the list keeps the stock backdrop of its display mode ('..tostring(mode or 'dropdown')..')')
 local placed=D.placed[list]
 C.guard(placed~=nil and placed.w==list:GetWidth() and placed.h==list:GetHeight() and placed.points==Points(list)
  and placed.level==list:GetFrameLevel() and list:GetFrameStrata()=='FULLSCREEN_DIALOG',
  tag..': the list keeps its stock size, anchors, strata and frame level',
  placed and (placed.w..'x'..placed.h..' -> '..list:GetWidth()..'x'..list:GetHeight()))
end
-- The shared tooltip with an owner (the harness has none): SetOwner records
-- it and GetOwner answers it, restored afterwards.
local function WithOwner(fn)
 local tip=GameTooltip
 local set,get=rawget(tip,'SetOwner'),rawget(tip,'GetOwner')
 rawset(tip,'SetOwner',function(self,owner) self._fixtureOwner=owner end)
 rawset(tip,'GetOwner',function(self) return self._fixtureOwner end)
 local ok,err=pcall(fn,tip)
 rawset(tip,'SetOwner',set);rawset(tip,'GetOwner',get)
 tip._fixtureOwner=nil
 assert(ok,err)
end
local function TipBase(tip,owner)
 tip:Hide();tip._fixtureOwner=owner;tip:Show()
 return tip._nexusSolidBase~=nil and tip._nexusSolidBase:IsShown()
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
Nexus.DisableOrdinaryAutomation()
P.Show()
C.setup(P.Render(Model())==true and NexusPanel and NexusPanel._menuBtn~=nil,'fixture: the panel renders with its Options button')
C.setup(T.EnsureTooltipBase()==true and GameTooltip._nexusSolidBase~=nil,'fixture: the shared tooltip has its Nexus base')

C.scenario('M0 before any Nexus menu, a stock menu gets no texture and no hook',function()
 local stats=T.Stats()
 local other=CreateFrame('Frame','FixtureEarlyAddonMenu',UIParent)
 EasyMenu({{text='Early one'},{text='Early two'}},other,'cursor',0,0)
 local list=List(1)
 C.setup(list:IsShown() and UIDROPDOWNMENU_OPEN_MENU==other,'M0: fixture: an addon menu shows in DropDownList1')
 C.guard(#Fills(list)==0 and #Fills(List(2))==0 and T.Stats().menuFills==stats.menuFills,
  'M0: no Nexus texture is made on a list no Nexus menu used')
 C.guard(list:GetScript('OnShow')==D.ListOnShow and list:GetScript('OnHide')==D.ListOnHide,
  'M0: its scripts are the stock ones (no hook before a Nexus menu)')
 Stock(1,nil,'M0')
 CloseDropDownMenus()
end)

C.scenario('M1 the Options menu: its shared list gets one opaque fill under its rows; the call and rows are as before',function()
 local before=Effects()
 local btn=NexusPanel._menuBtn
 local calls=#D.easy
 btn:GetScript('OnClick')(btn)
 local call=D.easy[#D.easy]
 C.guard(#D.easy==calls+1 and call.frame==_G.NexusPanelMoreMenu and call.anchor==btn
  and call.x==0 and call.y==0 and call.mode=='MENU',
  'M1: Options still opens one EasyMenu, at the Options button, in MENU mode')
 local list=List(1)
 if not C.setup(list:IsShown() and UIDROPDOWNMENU_OPEN_MENU==_G.NexusPanelMoreMenu and type(call.list)=='table',
  'M1: fixture: the Options menu shows in DropDownList1') then return end
 C.guard(#call.list>8 and RowsMatch(1,call.list) and D.maxButtons>=#call.list,
  'M1: every item has its own shown row with its label, handler and submenu; rows past the first eight are made on demand',#call.list)
 Opaque(1,'M1')
 Stock(1,'MENU','M1')
 C.expect(T.Stats().menuFills>=1,'M1: Theme counts the list fill it made',T.Stats().menuFills)
 C.guard(Effects()==before,'M1: opening the menu changes no saved data, Auto, action or send',Effects())
end)

C.scenario('M2 Options submenus reuse DropDownList2 with the root identity; filled while shown',function()
 local before=Effects()
 local appearance=Row(1,'Appearance: ')
 if not C.setup(appearance~=nil and appearance.hasArrow and type(appearance.menuList)=='table','M2: fixture: the Appearance row opens a list') then return end
 appearance:GetScript('OnEnter')(appearance)
 local list2=List(2)
 if not C.setup(list2:IsShown(),'M2: fixture: hovering Appearance shows DropDownList2') then return end
 C.guard(UIDROPDOWNMENU_OPEN_MENU==_G.NexusPanelMoreMenu and list2.parent==List(1) and RowsMatch(2,appearance.menuList),
  'M2: the submenu keeps the root identity, its stock parent link and its own rows and handlers')
 Opaque(2,'M2')
 Stock(2,'MENU','M2')
 C.expect(FillShown(1),'M2: the root list keeps its fill')
 local plain=FirstPlainRow(1)
 if C.setup(plain~=nil,'M2: fixture: a root row without a list') then
  plain:GetScript('OnEnter')(plain)
  C.expect(not list2:IsShown() and not FillShown(2) and FillShown(1),
   'M2: hovering a plain row closes the submenu (stock) and its fill goes with it; the root keeps its own')
 end
 local language=Row(1,'Language')
 if C.setup(language~=nil and language.hasArrow,'M2: fixture: the Language row opens a list') then
  language:GetScript('OnEnter')(language)
  C.expect(list2:IsShown() and RowsMatch(2,language.menuList) and FillShown(2) and #Fills(list2)==1,
   'M2: Language reuses DropDownList2 and its one fill shows again')
 end
 C.guard(Effects()==before,'M2: hovering submenus changes no saved data, Auto, action or send',Effects())
 CloseDropDownMenus()
 C.expect(not FillShown(1) and not FillShown(2),'M2: a close hides both fills')
end)

C.scenario('M3 a third level made on demand, the stock click, tooltip ownership, close while the global survives, reopen, toggle',function()
 local frame=CreateFrame('Frame','NexusFixtureMenu',UIParent,'UIDropDownMenuTemplate')
 local got={}
 local function Record(row,a1,a2,checked) got[#got+1]={row=row,a1=a1,a2=a2,checked=checked} end
 local deep={{text='Gamma',func=Record,arg1='g1',arg2='g2',tooltipTitle='Gamma tip'}}
 local items={{text='Alpha',hasArrow=true,menuList={{text='Beta',hasArrow=true,menuList=deep}}}}
 for i=1,11 do items[#items+1]={text='Row '..i,func=Record,arg1=i,arg2='x',checked=(i==3) or nil} end
 C.setup(_G.DropDownList3==nil,'M3: fixture: no third level exists yet')
 C.setup(T.OpenMenu(items,frame,'cursor',0,0)==true and List(1):IsShown() and UIDROPDOWNMENU_OPEN_MENU==frame,
  'M3: fixture: a Nexus menu with twelve rows shows')
 C.guard(RowsMatch(1,items),'M3: every row keeps its label, handler, arguments and submenu')
 Row(1,'Alpha'):GetScript('OnEnter')(Row(1,'Alpha'))
 local beta=Row(2,'Beta')
 if not C.setup(beta~=nil,'M3: fixture: the second level shows Beta') then return end
 beta:GetScript('OnEnter')(beta)
 local list3=List(3)
 if not C.setup(list3~=nil and list3:IsShown(),'M3: fixture: DropDownList3 was made on demand and shows') then return end
 C.guard(UIDROPDOWNMENU_OPEN_MENU==frame and list3.parent==List(2),'M3: the third level keeps the root identity and its stock parent link')
 C.expect(FillShown(1) and FillShown(2) and FillShown(3),'M3: every shown level of the Nexus menu is filled, the new one included')
 Opaque(3,'M3')
 Stock(3,'MENU','M3')
 local gamma=Row(3,'Gamma')
 WithOwner(function(tip)
  local lines=V.TooltipLines(gamma:GetScript('OnEnter'),gamma)
  C.expect(tip._fixtureOwner==gamma and lines[1]=='Gamma tip' and tip._nexusSolidBase:IsShown(),
   'M3: the tooltip of a row hover in a shown Nexus menu gets the opaque base')
 end)
 gamma:Click()
 C.guard(#got==1 and got[1].row==gamma and got[1].a1=='g1' and got[1].a2=='g2',
  'M3: the stock click calls the row\'s own handler once with its row and arguments')
 C.expect(not list3:IsShown() and not FillShown(3) and FillShown(1),'M3: the clicked level hides with its fill; the root keeps its own')
 local three=Row(1,'Row 3')
 three:Click()
 C.guard(#got==2 and got[2].row==three and got[2].a1==3 and got[2].a2=='x' and got[2].checked==true,
  'M3: a checked row passes its checked state to its handler')
 C.setup(UIDROPDOWNMENU_OPEN_MENU==frame,'M3: fixture: the open-menu global still names the Nexus menu after the close (contract item 6)')
 C.expect(not List(1):IsShown() and not FillShown(1) and not FillShown(2) and not FillShown(3),
  'M3: with every level hidden no fill shows, although the global still names the Nexus menu')
 WithOwner(function(tip)
  C.expect(not TipBase(tip,three),'M3: a tooltip owned by a row of a hidden Nexus list gets no base')
 end)
 local mid=T.Stats()
 C.setup(T.OpenMenu(items,frame,'cursor',0,0)==true and List(1):IsShown(),'M3: fixture: the same menu opens again')
 C.expect(FillShown(1),'M3: reopened, the list is filled again')
 local after=T.Stats()
 C.guard(after.menuFills==mid.menuFills and after.hooks==mid.hooks and after.textures==mid.textures and #Fills(List(1))==1,
  'M3: reopening makes no second texture or hook',after.textures-mid.textures)
 ToggleDropDownMenu(1,nil,frame,'cursor',0,0)
 C.expect(not List(1):IsShown() and not FillShown(1),'M3: the stock same-owner toggle hides the list and its fill')
 C.guard(#got==2,'M3: closing, reopening and toggling call no handler')
end)

C.scenario('M4 another addon and a game menu reuse the lists: no fill, their own surface and handlers; Nexus again is filled again',function()
 local before=Effects()
 local btn=NexusPanel._menuBtn
 btn:GetScript('OnClick')(btn)
 local appearance=Row(1,'Appearance: ')
 if not C.setup(appearance~=nil,'M4: fixture: the Options menu shows') then return end
 appearance:GetScript('OnEnter')(appearance)
 C.setup(FillShown(1) and FillShown(2),'M4: fixture: the Options menu and its Appearance list are filled')
 local regions1,regions2=#List(1).regions,#List(2).regions
 local other=CreateFrame('Frame','FixtureOtherAddonMenu',UIParent)
 local otherGot={}
 local otherItems={
  {text='Other one',func=function(row,a1,a2) otherGot[#otherGot+1]={row,a1,a2} end,arg1='o1',arg2='o2',tooltipTitle='Other tip'},
  {text='Other more',hasArrow=true,menuList={{text='Other deep'}}},
 }
 EasyMenu(otherItems,other,'cursor',0,0)
 if not C.setup(UIDROPDOWNMENU_OPEN_MENU==other and List(1):IsShown() and not List(2):IsShown(),
  'M4: fixture: another addon\'s menu reused DropDownList1; its initializer closed the Nexus submenu') then return end
 C.expect(not FillShown(1) and not FillShown(2),'M4: another owner\'s menu shows no Nexus fill on either list')
 C.guard(RowsMatch(1,otherItems),'M4: its rows are its own, with its own handlers')
 Stock(1,nil,'M4')
 Row(1,'Other more'):GetScript('OnEnter')(Row(1,'Other more'))
 C.setup(List(2):IsShown() and UIDROPDOWNMENU_OPEN_MENU==other,'M4: fixture: its submenu reuses DropDownList2')
 C.expect(not FillShown(2),'M4: the list Nexus filled before stays unfilled for the other submenu')
 Stock(2,nil,'M4 submenu')
 C.guard(#List(1).regions==regions1 and #List(2).regions==regions2,'M4: no texture is added to a list another menu shows')
 local one=Row(1,'Other one')
 WithOwner(function(tip)
  one:GetScript('OnEnter')(one)
  C.expect(tip._fixtureOwner==one and not tip._nexusSolidBase:IsShown(),'M4: its row tooltip gets no Nexus base')
 end)
 one:Click()
 C.guard(#otherGot==1 and otherGot[1][1]==one and otherGot[1][2]=='o1' and otherGot[1][3]=='o2',
  'M4: its own handler runs once with its row and arguments')
 local game=CreateFrame('Frame','FixtureGameMenu',UIParent)
 EasyMenu({{text='Game row'},{text='Game other'}},game,'cursor',0,0,'MENU')
 C.setup(List(1):IsShown() and UIDROPDOWNMENU_OPEN_MENU==game,'M4: fixture: a game menu in MENU mode reuses DropDownList1')
 C.expect(not FillShown(1),'M4: a game menu in the same display mode is still not filled')
 Stock(1,'MENU','M4 game')
 btn:GetScript('OnClick')(btn)
 C.expect(UIDROPDOWNMENU_OPEN_MENU==_G.NexusPanelMoreMenu and FillShown(1) and #Fills(List(1))==1,
  'M4: the Options menu again is filled again, with the same one fill')
 Stock(1,'MENU','M4 again')
 CloseDropDownMenus()
 C.guard(Effects()==before,'M4: the menus opened here changed no saved data, Auto, action or send',Effects())
end)

C.scenario('M5 the Appearance menu and the Plan hub menu route through the same owner',function()
 local before=Effects()
 local calls=#D.easy
 C.setup(T.ShowMenu(NexusPanel._menuBtn)==true,'M5: fixture: Theme.ShowMenu opens')
 local call=D.easy[#D.easy]
 C.guard(#D.easy==calls+1 and call.frame==_G.NexusAppearanceMenu and call.mode=='MENU' and call.x==0 and call.y==0,
  'M5: the Appearance menu is still one EasyMenu in MENU mode')
 C.expect(UIDROPDOWNMENU_OPEN_MENU==_G.NexusAppearanceMenu and FillShown(1),'M5: the Appearance menu is filled')
 Opaque(1,'M5')
 CloseDropDownMenus()
 -- The hub menu is the route without the full UI workspaces.
 local workspaces=Nexus.FullUIWorkspaces
 Nexus.FullUIWorkspaces=nil
 local ok,shown=pcall(P.ShowHub,'plan',NexusPanel._menuBtn)
 Nexus.FullUIWorkspaces=workspaces
 C.setup(ok and shown==true,'M5: fixture: the Plan hub menu opens',shown)
 C.expect(UIDROPDOWNMENU_OPEN_MENU==_G.NexusPanelHubMenu and FillShown(1),'M5: the Plan hub menu is filled')
 C.guard(D.easy[#D.easy].frame==_G.NexusPanelHubMenu and D.easy[#D.easy].mode=='MENU','M5: the hub menu is still one EasyMenu in MENU mode')
 CloseDropDownMenus()
 C.expect(not FillShown(1),'M5: closed, no fill shows')
 C.guard(Effects()==before,'M5: opening these menus changed no saved data, Auto, action or send',Effects())
end)

C.scenario('M6 a level only another addon ever showed stays stock',function()
 local other=CreateFrame('Frame','FixtureDeepAddonMenu',UIParent)
 local items={{text='L1',hasArrow=true,menuList={{text='L2',hasArrow=true,menuList={{text='L3',hasArrow=true,menuList={{text='L4'}}}}}}}}
 C.setup(_G.DropDownList4==nil,'M6: fixture: no fourth level exists yet')
 EasyMenu(items,other,'cursor',0,0,'MENU')
 for level,label in ipairs({'L1','L2','L3'}) do
  local row=Row(level,label)
  if row then row:GetScript('OnEnter')(row) end
 end
 local list4=List(4)
 if not C.setup(list4~=nil and list4:IsShown() and UIDROPDOWNMENU_OPEN_MENU==other,'M6: fixture: the addon\'s fourth level shows') then return end
 C.guard(#Fills(list4)==0 and list4:GetScript('OnShow')==D.ListOnShow and list4:GetScript('OnHide')==D.ListOnHide,
  'M6: the new level gets no Nexus texture and keeps its stock scripts')
 C.expect(not FillShown(1) and not FillShown(2) and not FillShown(3),'M6: no list Nexus filled before shows a fill for this menu')
 Stock(4,'MENU','M6')
 CloseDropDownMenus()
end)

C.scenario('M7 the Options button toggles its own shown menu; any other state opens it (issue #165)',function()
 local before=Effects()
 local btn=NexusPanel._menuBtn
 local click=btn:GetScript('OnClick')
 local function OptionsShown()
  return List(1):IsShown() and UIDROPDOWNMENU_OPEN_MENU==_G.NexusPanelMoreMenu
 end
 CloseDropDownMenus()
 click(btn)
 C.setup(OptionsShown() and FillShown(1),'M7: fixture: the first click opens the filled Options menu')
 local items=D.easy[#D.easy].list
 click(btn)
 C.expect(not List(1):IsShown() and not List(2):IsShown() and not FillShown(1),
  'M7: a second click on Options while its menu shows leaves it closed, with no fill')
 click(btn)
 C.expect(OptionsShown() and FillShown(1) and RowsMatch(1,D.easy[#D.easy].list) and #D.easy[#D.easy].list==#items,
  'M7: a third click opens it again with every row and handler and its fill')
 local appearance=Row(1,'Appearance: ')
 if C.setup(appearance~=nil,'M7: fixture: the Appearance row') then
  appearance:GetScript('OnEnter')(appearance)
  C.setup(List(2):IsShown() and UIDROPDOWNMENU_MENU_LEVEL==2,'M7: fixture: its submenu shows (menu level 2)')
  click(btn)
  C.expect(not List(1):IsShown() and not List(2):IsShown() and not FillShown(1) and not FillShown(2),
   'M7: clicking Options with a submenu open closes the whole menu')
 end
 click(btn)
 C.setup(OptionsShown(),'M7: fixture: open again')
 CloseDropDownMenus()
 C.setup(UIDROPDOWNMENU_OPEN_MENU==_G.NexusPanelMoreMenu and not List(1):IsShown(),
  'M7: fixture: a stock close hides the menu while the open-menu global still names it')
 click(btn)
 C.expect(OptionsShown() and FillShown(1),'M7: after a stock close (Escape), one click opens Options')
 List(1):Hide()
 click(btn)
 C.expect(OptionsShown() and FillShown(1),'M7: after a timeout hide of its list, one click opens Options')
 C.setup(T.ShowMenu(btn)==true and UIDROPDOWNMENU_OPEN_MENU==_G.NexusAppearanceMenu and List(1):IsShown(),
  'M7: fixture: another Nexus menu (Appearance) now shows in DropDownList1')
 click(btn)
 C.expect(OptionsShown() and FillShown(1),'M7: with another Nexus menu shown, one click opens Options')
 local other=CreateFrame('Frame','FixtureOpenerAddonMenu',UIParent)
 EasyMenu({{text='Foreign one'}},other,'cursor',0,0)
 C.setup(UIDROPDOWNMENU_OPEN_MENU==other and List(1):IsShown() and not FillShown(1),
  'M7: fixture: another addon\'s menu reused DropDownList1, unfilled')
 click(btn)
 C.expect(OptionsShown() and FillShown(1) and RowsMatch(1,D.easy[#D.easy].list),
  'M7: with another addon\'s menu shown, one click opens Options with its own rows and fill')
 CloseDropDownMenus()
 C.guard(Effects()==before,'M7: opening and closing Options changed no saved data, Auto, action or send',Effects())
end)

C.scenario('M8 ordinary HUD renders between Options clicks keep the toggle; a foreign menu survives them (native test.163012)',function()
 local before=Effects()
 local btn=NexusPanel._menuBtn
 local click=btn:GetScript('OnClick')
 local function OptionsShown()
  return List(1):IsShown() and UIDROPDOWNMENU_OPEN_MENU==_G.NexusPanelMoreMenu
 end
 CloseDropDownMenus()
 local opens=#D.easy
 local seq={}
 for i=1,4 do
  P.Render(Model())
  click(btn)
  P.Render(Model())
  seq[#seq+1]=OptionsShown() and 'open' or 'closed'
 end
 C.guard(table.concat(seq,' ')=='open closed open closed' and #D.easy-opens==2,
  'M8: closed, open, closed, open with a render before and after each click; one EasyMenu per opening',
  table.concat(seq,' ')..' opens='..(#D.easy-opens))
 click(btn)
 local appearance=Row(1,'Appearance: ')
 if C.setup(appearance~=nil,'M8: fixture: the Appearance row') then
  appearance:GetScript('OnEnter')(appearance)
  P.Render(Model())
  C.guard(List(2):IsShown() and FillShown(1) and FillShown(2),'M8: a render keeps an open submenu and both fills')
  click(btn)
  C.guard(not List(1):IsShown() and not List(2):IsShown(),'M8: after the render one click still closes every level')
 end
 local other=CreateFrame('Frame','FixtureRenderAddonMenu',UIParent)
 click(btn)
 EasyMenu({{text='Foreign two'}},other,'cursor',0,0)
 P.Render(Model())
 C.guard(UIDROPDOWNMENU_OPEN_MENU==other and List(1):IsShown() and not FillShown(1) and Row(1,'Foreign two')~=nil,
  'M8: a foreign menu that reused the list after Options stays shown and unfilled through a Nexus render')
 click(btn)
 C.guard(OptionsShown() and FillShown(1),'M8: then one click opens Options over it, not a close of the foreign menu')
 CloseDropDownMenus()
 C.guard(Effects()==before,'M8: clicks and renders changed no saved data, Auto, action or send',Effects())
end)

C.scenario('M9 Pause and Resume through the stock row click: the list hides, then the owner runs once (native test.163012)',function()
 local SP=Nexus.SessionPause
 local btn=NexusPanel._menuBtn
 local click=btn:GetScript('OnClick')
 local function Title() return V.Plain(NexusPanel._contextTitle:GetText() or '') end
 local calls={pause=0,resume=0}
 local pause,resume=SP.Pause,SP.Resume
 SP.Pause=function(...) calls.pause=calls.pause+1;return pause(...) end
 SP.Resume=function(...) calls.resume=calls.resume+1;return resume(...) end
 local before=Effects()
 if SP.IsPaused() then resume() end
 local epoch=SP.Status().epoch
 CloseDropDownMenus()
 P.Render(Model())
 click(btn)
 P.Render(Model())
 local row=Row(1,'Pause Nexus for this session')
 if C.setup(row~=nil and FillShown(1),'M9: fixture: the open Options menu offers Pause after a render') then
  local hiddenFirst
  local func=row.func
  row.func=function(...) hiddenFirst=not List(1):IsShown();return func(...) end
  row:GetScript('OnClick')(row)
  row.func=func
  C.guard(hiddenFirst==true and calls.pause==1 and SP.IsPaused() and SP.Status().epoch==epoch+1,
   'M9: the stock row hides its list before the callback, which pauses the owner once',tostring(hiddenFirst)..' '..calls.pause)
  C.guard(Title():find('Nexus paused',1,true)~=nil and not List(1):IsShown() and not FillShown(1),
   'M9: the title says Nexus paused at once and the menu is closed',Title())
 end
 P.Render(Model())
 click(btn)
 P.Render(Model())
 row=Row(1,'Resume Nexus')
 if C.setup(row~=nil and Row(1,'Pause Nexus')==nil,'M9: fixture: reopened after a render, Options offers Resume Nexus') then
  row:GetScript('OnClick')(row)
  C.guard(calls.resume==1 and not SP.IsPaused() and SP.Status().epoch==epoch+2,
   'M9: the stock Resume row click resumes the owner exactly once',calls.resume..' '..SP.Status().epoch)
  C.guard(Title():find('paused',1,true)==nil and not List(1):IsShown(),'M9: the paused title goes at once',Title())
  P.Render(Model())
  C.guard(Title():find('paused',1,true)==nil,'M9: an ordinary render after Resume keeps the title unpaused',Title())
 end
 click(btn)
 C.guard(Row(1,'Pause Nexus for this session')~=nil and Row(1,'Resume Nexus')==nil,'M9: reopened Options offers Pause again')
 CloseDropDownMenus()
 SP.Pause,SP.Resume=pause,resume
 C.guard(calls.pause==1 and calls.resume==1 and Effects()==before and Nexus.RecomputeStats().autoEnabled==false,
  'M9: one Pause, one Resume; Auto stays OFF; no saved data, action or send',Effects())
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(Nexus-owned native menu surfaces over a synthetic FrameXML dropdown; native opacity, order and hit testing NOT RUN)')
