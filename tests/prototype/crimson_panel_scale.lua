-- Issue #170: Main panel size, 50%-150% in 5% steps with Reset to 100%, in
-- the Options menu's Panel section. The chosen size (saved key panelScale)
-- is the main panel's fit ceiling: effective = max(0.5, min(requested,
-- (screenW-24)/width, (screenH-24)/height)); a temporary reduction is shown
-- ("Reduced to fit your screen") and never saved. Only the main panel and
-- its children scale.
-- Z1 absent panelScale reads 100%; rendering and opening Options write no key;
-- Z2 the Options size rows: Larger / Smaller by 5%, 50%, 150% and Reset to
--    100% (which removes the key) set the chosen and applied size;
-- Z3 an explicit request is clamped to 50%-150% and stepped to 5%; a
--    non-finite or non-number request writes nothing;
-- Z4 a malformed or out-of-range saved value reads as 100% and is not
--    rewritten by reading, rendering or opening Options;
-- Z5 a screen too narrow for the chosen size reduces the applied size, says
--    so, keeps the choice, and returns to it when the screen fits again;
--    invalid screen dimensions keep a finite scale and write nothing;
-- Z6 the generic FitToScreen keeps its ceiling of 1 for every other caller
--    and takes a ceiling for the main panel;
-- Z7 a size change keeps the panel's physical top-left corner (then the
--    smallest clamp to the screen) and writes no panelX / panelY;
-- Z8 a drag at 150% saves its centre in UIParent units; a render during an
--    active drag changes neither the scale nor the anchor;
-- Z9 no other frame's scale changes (Wishlist overlay, independent windows,
--    the server's own difficulty HUD);
-- Z10 a future-format (read-only) saved root keeps panelScale in the
--    session-only root and its saved data byte for byte.
-- Categories (view_regression_support): EXPECT fails at c7e4d7cd (no size
-- control, FitToScreen has no ceiling), GUARD already held, SETUP is the
-- fixture. Native seams set by the test: UIParent size and scales and the
-- panel's effective scale / corner reads (the harness has no layout
-- engine). Native pixels, UI scale and screen edges are NOT RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('crimson_panel_scale')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local P,LM=Nexus.Panel,Nexus.LayoutMetrics
local RM=G.RegionMethods()
local function Model()
 return {status='ready',level=40,auto=false,cards={},recommendation='',
  progress={wishlistName='Size plan',total=6,owned=2,missing={'Hollow Bell'},shed={},toLock={},unknownTomes={}}}
end
local function Effects()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end
-- Every SetScale call, by frame.
local scaled={}
do
 local set=RM.SetScale
 RM.SetScale=function(self,v) scaled[#scaled+1]=self;return set(self,v) end
end
-- The screen: UIParent's size in its own units at UI scale 1.
UIParent:SetSize(1920,1080)
-- The panel's effective scale follows its own scale (UIParent at 1); its
-- corner is read from where the test says the client draws it.
local root
local corner={left=600,top=700}
local function Boot()
 P.Show()
 C.setup(P.Render(Model())==true and NexusPanel:IsShown(),'fixture: the panel renders')
 root=NexusPanel
 rawset(root,'GetEffectiveScale',function(self) return self:GetScale() end)
 rawset(root,'GetLeft',function() return corner.left end)
 rawset(root,'GetTop',function() return corner.top end)
end
local function Saved() return P.SavedLayoutRoot() end
local function SizeMenu()
 for _,item in ipairs(P.MoreMenuItems(root and root._menuBtn)) do
  if type(item.text)=='string' and item.text:find('^Main panel size') then return item end
 end
end
local function Row(menu,prefix)
 for _,item in ipairs(menu and menu.menuList or {}) do
  if type(item.text)=='string' and item.text:sub(1,#prefix)==prefix then return item end
 end
end
local function Click(prefix)
 local row=Row(SizeMenu(),prefix)
 if not row or type(row.func)~='function' then return false end
 row.func(row,row.arg1,row.arg2)
 P.Render(Model())
 return true
end
local function Near(a,b) return type(a)=='number' and math.abs(a-b)<0.0005 end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
Nexus.DisableOrdinaryAutomation()
Boot()

C.scenario('Z1 absent panelScale reads 100%; rendering and opening Options write nothing',function()
 C.setup(rawget(NexusDB,'panelScale')==nil,'Z1: fixture: no saved panelScale')
 P.Render(Model())
 local menu=SizeMenu()
 C.expect(menu~=nil and menu.hasArrow==true and type(menu.menuList)=='table','Z1: Options has a Main panel size list')
 C.expect(menu and menu.text=='Main panel size: 100%','Z1: it shows the chosen size, 100%',menu and menu.text)
 C.expect(Near(root:GetScale(),1),'Z1: the panel is at 100%',root:GetScale())
 C.guard(rawget(NexusDB,'panelScale')==nil,'Z1: rendering and opening Options write no panelScale')
end)

C.scenario('Z2 Larger, Smaller, 50%, 150% and Reset to 100% from the Options size list',function()
 local before=Effects()
 C.expect(Click('Larger') and Saved().panelScale==1.05 and Near(root:GetScale(),1.05),'Z2: Larger sets and applies 105%',root:GetScale())
 C.expect(SizeMenu().text=='Main panel size: 105%','Z2: the list names the chosen 105%',SizeMenu().text)
 C.expect(Click('Smaller') and Click('Smaller') and Saved().panelScale==0.95 and Near(root:GetScale(),0.95),
  'Z2: Smaller twice sets and applies 95%',root:GetScale())
 C.expect(Click('50%') and Saved().panelScale==0.5 and Near(root:GetScale(),0.5),'Z2: 50% sets and applies 50%')
 C.expect(Click('Smaller') and Saved().panelScale==0.5,'Z2: Smaller at 50% stays at 50%')
 C.expect(Click('150%') and Saved().panelScale==1.5 and Near(root:GetScale(),1.5),'Z2: 150% sets and applies 150%')
 C.expect(Click('Larger') and Saved().panelScale==1.5,'Z2: Larger at 150% stays at 150%')
 local hundred=Row(SizeMenu(),'100%')
 C.expect(hundred and hundred.checked~=true and Row(SizeMenu(),'150%').checked==true,'Z2: the chosen preset is checked')
 C.expect(Click('Reset to 100%') and rawget(Saved(),'panelScale')==nil and Near(root:GetScale(),1),
  'Z2: Reset to 100% removes the key and applies 100%')
 C.guard(Effects()==before,'Z2: size changes take no action, send or Auto',Effects())
end)

C.scenario('Z3 an explicit request is clamped and stepped; a non-number writes nothing',function()
 for _,case in ipairs({{2,1.5},{0.37,0.5},{1.234,1.25},{1.026,1.05},{0.5,0.5}}) do
  P.SetPanelScale(case[1])
  C.expect(Saved().panelScale==case[2],'Z3: a request of '..case[1]..' is saved as '..case[2],Saved().panelScale)
 end
 P.ResetPanelScale()
 for _,bad in ipairs({0/0,math.huge,-math.huge,'1.2',true}) do
  C.expect(P.SetPanelScale(bad)==false and rawget(Saved(),'panelScale')==nil,'Z3: a request of '..tostring(bad)..' writes nothing')
 end
end)

C.scenario('Z4 a malformed or out-of-range saved value reads as 100% and is not rewritten',function()
 for _,bad in ipairs({'big',9,-1,0.2,1.51,0/0,{}}) do
  NexusDB.panelScale=bad
  P.Render(Model())
  local menu=SizeMenu()
  C.expect(Near(root:GetScale(),1) and menu.text=='Main panel size: 100%','Z4: a saved '..tostring(bad)..' reads as 100%',root:GetScale())
  C.guard(NexusDB.panelScale==bad or (bad~=bad and NexusDB.panelScale~=NexusDB.panelScale),
   'Z4: a saved '..tostring(bad)..' is left as it is')
 end
 NexusDB.panelScale=1.25
 P.Render(Model())
 C.expect(Near(root:GetScale(),1.25),'Z4: a valid saved 1.25 applies')
 NexusDB.panelScale=nil
 P.Render(Model())
end)

C.scenario('Z5 a narrow screen reduces the applied size and says so; the choice is kept',function()
 P.SetPanelScale(1.5)
 C.setup(root:GetWidth()==420 and root:GetHeight()<700,'Z5: fixture: the panel is 420 wide and under 700 tall',root:GetHeight())
 UIParent:SetSize(640,1080)
 P.Render(Model())
 C.expect(Near(root:GetScale(),616/420),'Z5: on a 640-wide screen the applied size is (640-24)/420',root:GetScale())
 C.expect(Saved().panelScale==1.5,'Z5: the chosen 150% stays saved')
 local menu=SizeMenu()
 C.expect(menu.text=='Main panel size: 150%' and Row(menu,'Reduced to fit your screen')~=nil,
  'Z5: the list keeps 150% and says Reduced to fit your screen',menu.text)
 UIParent:SetSize(1920,1080)
 P.Render(Model())
 C.expect(Near(root:GetScale(),1.5) and Row(SizeMenu(),'Reduced to fit')==nil,'Z5: on a screen that fits it returns to 150%')
 UIParent:SetSize(0,0)
 P.Render(Model())
 local s=root:GetScale()
 C.expect(type(s)=='number' and s==s and s>=0.5 and s<=1.5 and Saved().panelScale==1.5,
  'Z5: unreadable screen dimensions keep a finite scale and the choice',s)
 UIParent:SetSize(1920,1080)
 P.ResetPanelScale()
 P.Render(Model())
end)

C.scenario('Z6 FitToScreen keeps a ceiling of 1 for other callers and takes a ceiling for the main panel',function()
 local f=CreateFrame('Frame','FixtureScaleWindow',UIParent)
 f:SetSize(420,400)
 UIParent:SetSize(1000,700)
 C.expect(LM.FitToScreen(f)==1 and f:GetScale()==1,'Z6: a window that fits stays at 1')
 C.expect(LM.FitToScreen(f,nil,1.5)==1.5,'Z6: with a ceiling of 1.5 it may grow to 1.5')
 UIParent:SetSize(1000,524)
 C.expect(Near(LM.FitToScreen(f,nil,1.5),1.25),'Z6: (524-24)/400 caps it at 1.25')
 C.expect(Near(LM.FitToScreen(f),1),'Z6: without a ceiling it is 1 as before')
 UIParent:SetSize(1000,224)
 C.expect(LM.FitToScreen(f,nil,1.5)==nil,'Z6: an implausibly small screen is not acted on (as before)')
 for _,bad in ipairs({0/0,math.huge,-1,'x'}) do
  UIParent:SetSize(1000,700)
  C.expect(LM.FitToScreen(f,nil,bad)==1,'Z6: a ceiling of '..tostring(bad)..' is the default 1')
 end
 UIParent:SetSize(1920,1080)
end)

C.scenario('Z7 a size change keeps the physical top-left corner and writes no position',function()
 P.ResetPanelScale();P.Render(Model())
 Saved().panelX,Saved().panelY=nil,nil
 corner.left,corner.top=600,700
 Click('150%')
 local p,rel,relP,x,y=root:GetPoint(1)
 C.expect(root:GetNumPoints()==1 and p=='TOPLEFT' and rel==UIParent and relP=='BOTTOMLEFT' and Near(x,400) and Near(y,700/1.5),
  'Z7: at 150% the corner 600,700 (physical) is anchored at 400,466.7 panel units',tostring(p)..' '..tostring(x)..','..tostring(y))
 C.guard(Saved().panelX==nil and Saved().panelY==nil,'Z7: a size change writes no panelX / panelY')
 -- Near the bottom edge the panel moves up just enough to stay whole.
 corner.left,corner.top=600,100
 Click('Reset to 100%')
 local _,_,_,_,y2=root:GetPoint(1)
 C.expect(Near(y2,root:GetHeight()),'Z7: a corner that would leave the bottom is clamped to the panel height',y2)
 corner.left,corner.top=600,700
 P.Render(Model())
end)

C.scenario('Z8 a drag at 150% saves UIParent units; a render during a drag keeps scale and anchor',function()
 Click('150%')
 rawset(root,'StartMoving',function() end);rawset(root,'StopMovingOrSizing',function() end)
 local cx,cy=500,400
 rawset(root,'GetCenter',function() return cx,cy end)
 rawset(UIParent,'GetCenter',function() return 960,540 end)
 local grip=root._dragGrip
 -- Held-Shift scope (the accepted Shift start gate): this drag is the
 -- intended real move, so Shift answers as held (the client's 1) from its
 -- start through its saved centre. The exact previous query returns on every
 -- exit; an error is raised again after that.
 local shiftBefore=IsShiftKeyDown
 IsShiftKeyDown=function() return 1 end
 local heldOk,heldErr=pcall(function()
 grip:GetScript('OnDragStart')(grip,'LeftButton')
 cx,cy=600,420
 local n=#scaled
 local anchors=root:GetNumPoints()
 local clear=0
 rawset(root,'ClearAllPoints',function(self) clear=clear+1;return RM.ClearAllPoints(self) end)
 UIParent:SetSize(1920,600)
 P.Render(Model())
 C.expect(#scaled==n and clear==0,'Z8: a render during the drag neither rescales nor re-anchors the panel',(#scaled-n)..'/'..clear)
 grip:GetScript('OnDragStop')(grip)
 rawset(root,'ClearAllPoints',nil)
 C.expect(Saved().panelX==-60 and Saved().panelY==90,'Z8: the centre 600,420 at 150% is saved as -60,90',
  tostring(Saved().panelX)..','..tostring(Saved().panelY))
 UIParent:SetSize(1920,1080)
 P.Render(Model())
 rawset(root,'GetCenter',nil);rawset(UIParent,'GetCenter',nil)
 Saved().panelX,Saved().panelY=nil,nil
 end)
 IsShiftKeyDown=shiftBefore
 -- Cleanup only after an error: a move left active ends by the grip's real drag-stop.
 if not heldOk and P._panelDrag then local stop=grip:GetScript('OnDragStop');if stop then pcall(stop,grip) end end
 if not heldOk then error(heldErr,0) end
end)

C.scenario('Z9 only the main panel is scaled',function()
 local n=#scaled
 Click('Larger');Click('50%');Click('Reset to 100%')
 local others={}
 for i=n+1,#scaled do if scaled[i]~=root then others[#others+1]=tostring(scaled[i]:GetName()) end end
 C.expect(#others==0,'Z9: size changes rescale no other frame (overlay, windows, server HUD)',table.concat(others,','))
end)

C.scenario('Z10 a future-format saved root keeps the size session-only',function()
 local db=F.Database({version=6})
 local saved=F.Serialize(db)
 H=F.Boot(db,function(h) F.OrbService(h) end)
 P,LM=Nexus.Panel,Nexus.LayoutMetrics
 UIParent:SetSize(1920,1080)
 C.setup(Nexus.MainInternals.SavedRootReadOnlyV1(NexusDB)~=nil,'Z10: fixture: the saved root is read-only (future format)')
 Boot()
 Click('150%')
 C.expect(Saved()~=NexusDB and Saved().panelScale==1.5 and Near(root:GetScale(),1.5),'Z10: the size applies from the session-only root')
 C.guard(F.Serialize(NexusDB)==saved,'Z10: the saved root is unchanged byte for byte')
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(main panel size control and fit over the harness; native pixels, UI scale and screen edges NOT RUN)')
