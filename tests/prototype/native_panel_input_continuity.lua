-- Native test.163012 (b1ef408): a second click on the visible Options button
-- left its menu open (issue #165, N01), and neither a plain-left drag from the
-- Build line nor one from the grip moved the panel (issue #168, N03-N04).
-- Shared source boundary: Panel.Render hid the whole movable root on every
-- refresh, an unchanged one included, and showed it again in the same call.
-- No frame is drawn inside one Lua call, so that hide never kept a partial
-- tree off screen; on success it only reached the root and every shown
-- descendant (the Options button, the grip, the Build / Wishlist lines) as a
-- hide while the player's pointer could be pressing or moving them. A
-- failing render still hides the root and keeps it hidden.
-- C1 an ordinary render of the shown panel (unchanged, changed text, changed
--    layout, Details) hides neither the root nor any shown descendant;
-- C2 under the input-loss model below, a click on Options pressed before an
--    ordinary render and released after it is delivered: closed -> open ->
--    closed -> open, one menu open per opening click;
-- C3 under the same model, a move from the Build line, the Wishlist line,
--    the grip and the background keeps moving across ordinary renders, is
--    stopped once by its release and saves its position once;
-- C4 a failing render still hides the root, keeps it hidden and ends an
--    active move once; the next good render shows the panel again;
-- C5 the player's own hide and a menu window's suppression still keep the
--    panel hidden through a render, and the first render of a hidden panel
--    shows it only after its commit.
-- Input-loss model (HYPOTHESIS, not the client): the triage hypothesis that
-- the client cancels a button press or a frame's move when that frame or an
-- ancestor is hidden. Here a hide that reaches the pressed button or the
-- moving root (OnHide, propagated to every shown descendant as the client
-- does) cancels it. Native pointer capture, drag threshold, mouse focus and
-- hit order are NOT RUN; C1 is the source invariant this model depends on.
-- Categories (view_regression_support): EXPECT is behaviour this correction
-- adds (fails at b1ef408: every successful render hides the root), GUARD
-- already held and must keep holding, SETUP is the fixture.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('native_panel_input_continuity')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local P=Nexus.Panel
local RM=G.RegionMethods()
RM.RegisterForDrag=function(self,...) self._dragButtons={...} end

local board={observed=true,title='Ember Watch',lines={'Light 4 braziers'},rewards={}}
Nexus.CallboardStatus.GetSummary=function() return board end
local function Model(o)
 o=o or {}
 return {status=o.status or 'ready',level=40,auto=false,cards=o.cards or {},recommendation=o.recommendation or '',
  progress={wishlistName=o.wishlist or 'Ash',total=6,owned=2,missing={'Cinder Lattice x2 (Rare:x2)','Hollow Bell'},
   shed={'Ashen Tithe'},toLock={'Gravecall Chorus'},unknownTomes={'Frostwake Sigil'}},
  bestDps={dummy={dps=1200}}}
end
local function Effects()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
Nexus.DisableOrdinaryAutomation()
P.Show()
C.setup(P.Render(Model())==true and NexusPanel:IsShown(),'fixture: the panel renders')
local root=NexusPanel

-- The client's hide reaches every shown descendant (OnHide) and a show
-- brings their OnShow back; the harness fires only the frame's own script.
local hidden={}
local function Propagate(f,script,seen)
 for _,c in ipairs(f.children or {}) do
  if c.shown and not seen[c] then
   seen[c]=true
   if script=='OnHide' then hidden[c]=(hidden[c] or 0)+1 end
   local fn=c.scripts and c.scripts[script]
   if fn then fn(c) end
   Propagate(c,script,seen)
  end
 end
end
rawset(root,'Hide',function(self)
 local was=self.shown;RM.Hide(self)
 if was then hidden[self]=(hidden[self] or 0)+1;Propagate(self,'OnHide',{}) end
end)
rawset(root,'Show',function(self) local was=self.shown;RM.Show(self);if not was then Propagate(self,'OnShow',{}) end end)
local function Hides(f) return hidden[f] or 0 end
local function ClearHides() hidden={} end

-- The input-loss model (see the header).
local Input={}
function Input.Press(btn) Input.pressed,Input.lost=btn,false;Input.mark=Hides(btn) end
function Input.Release()
 local btn=Input.pressed;Input.pressed=nil
 if Hides(btn)~=Input.mark then Input.lost=true;return false end
 btn:GetScript('OnClick')(btn,'LeftButton')
 return true
end
local Move={starts=0,stops=0,x=400,y=300,moving=false,cancelled=0}
rawset(root,'StartMoving',function() Move.starts=Move.starts+1;Move.moving=true;Move.mark=Hides(root) end)
rawset(root,'StopMovingOrSizing',function() Move.stops=Move.stops+1;Move.moving=false end)
rawset(root,'GetCenter',function() return Move.x,Move.y end)
rawset(UIParent,'GetCenter',function() return 960,540 end)
-- The pointer moves by dx: the root follows only while its move is live.
local function Pointer(dx)
 if Move.moving and Hides(root)~=Move.mark then Move.moving=false;Move.cancelled=Move.cancelled+1 end
 if Move.moving then Move.x=Move.x+dx end
end
local function Saved() local s=P.SavedLayoutRoot();return s.panelX,s.panelY end
local function ResetMove()
 Move.starts,Move.stops,Move.x,Move.y,Move.moving,Move.cancelled=0,0,400,300,false,0
 local s=P.SavedLayoutRoot();s.panelX,s.panelY=nil,nil
end

-- A minimal stand-in for the shared list Options opens (the full stock
-- lifecycle is native_dropdown_ownership M7-M9): EasyMenu shows
-- DropDownList1 for its frame and records the open-menu global, a close
-- hides it.
local menu={opens=0}
local list=CreateFrame('Frame','DropDownList1',UIParent);list:Hide()
function EasyMenu(items,frame) menu.opens=menu.opens+1;UIDROPDOWNMENU_OPEN_MENU=frame;list:Show() end
function CloseDropDownMenus() list:Hide() end
local function OptionsShown() return list:IsShown() and UIDROPDOWNMENU_OPEN_MENU==_G.NexusPanelMoreMenu end

C.scenario('C1 an ordinary render of the shown panel hides neither the root nor a shown descendant',function()
 local parts={root=root,options=root._menuBtn,build=root._contextBuildHit,wishlist=root._contextWishlistHit,
  title=root._contextTitleHit}
 for name,f in pairs(parts) do C.setup(f~=nil and f:IsShown(),'C1: fixture: the '..name..' part is shown') end
 local cases={
  {'an unchanged render',Model()},
  {'a render with changed text',Model({wishlist='Ember'})},
  {'a render with a changed layout',Model({cards={{text='Frostwake Sigil (Rare)'}},recommendation='Take Frostwake Sigil'})},
  {'a status-only render',Model({status='waiting for the next board'})},
 }
 for _,case in ipairs(cases) do
  ClearHides()
  local ok=P.Render(case[2])
  local lost={}
  for name,f in pairs(parts) do if Hides(f)>0 then lost[#lost+1]=name end end
  table.sort(lost)
  C.expect(ok==true and root:IsShown() and #lost==0,'C1: '..case[1]..' hides no shown panel part',table.concat(lost,','))
 end
 ClearHides()
 local ok=pcall(P.Render,P._lastModel)
 C.expect(ok and root:IsShown() and Hides(root)==0,'C1: repainting the committed model (the Pause / Resume repaint) hides no part',Hides(root))
end)

C.scenario('C2 a click on Options straddling an ordinary render is delivered: closed, open, closed, open',function()
 local btn=root._menuBtn
 CloseDropDownMenus();menu.opens=0
 local before=Effects()
 local seq={}
 for i=1,4 do
  Input.Press(btn)
  P.Render(Model())
  local delivered=Input.Release()
  seq[#seq+1]=(delivered and 'd' or 'lost')..':'..(OptionsShown() and 'open' or 'closed')
  P.Render(Model())
 end
 local got=table.concat(seq,' ')
 C.expect(got=='d:open d:closed d:open d:closed','C2: four clicks across renders toggle the menu each time',got)
 C.expect(menu.opens==2,'C2: each opening click opens the menu exactly once',menu.opens)
 C.guard(Effects()==before,'C2: the clicks changed no Auto, action or send')
 CloseDropDownMenus()
end)

C.scenario('C3 a Shift-held left move keeps moving across ordinary renders and saves once',function()
 -- Held-Shift scope (the accepted Shift start gate): these moves are the
 -- intended real ones, so Shift answers as held (the client's 1) through the
 -- loop. The exact previous query returns on every exit; an error is raised
 -- again after that.
 local shiftBefore=IsShiftKeyDown
 IsShiftKeyDown=function() return 1 end
 local heldOk,heldErr=pcall(function()
 local surfaces={{'Build line',root._contextBuildHit},{'Wishlist line',root._contextWishlistHit},
  {'grip',root._dragGrip},{'background',root}}
 for _,s in ipairs(surfaces) do
  local name,hit=s[1],s[2]
  C.setup(hit~=nil,'C3: fixture: the '..name..' exists')
  if hit then
   ResetMove()
   hit:GetScript('OnDragStart')(hit,'LeftButton')
   C.setup(P._panelDrag~=nil and Move.starts==1,'C3: fixture: a move from the '..name..' starts')
   Pointer(10)
   P.Render(Model())
   Pointer(10)
   P.Render(Model({wishlist='Ember'}))
   Pointer(10)
   C.expect(Move.cancelled==0 and Move.x==430,'C3: from the '..name..' the root follows the pointer across renders',
    'x='..Move.x..' cancelled='..Move.cancelled)
   C.guard(P._panelDrag~=nil and Move.stops==0 and Saved()==nil,'C3: from the '..name..' a render neither ends the move nor saves')
   hit:GetScript('OnDragStop')(hit)
   root:GetScript('OnMouseUp')(root)
   local x=Saved()
   C.guard(Move.stops==1 and P._panelDrag==nil,'C3: from the '..name..' the release stops it once',Move.stops)
   C.expect(x==430-960,'C3: from the '..name..' the moved position is saved once',tostring(x))
  end
 end
 P.Render(Model())
 end)
 IsShiftKeyDown=shiftBefore
 -- Cleanup only after an error: a move left active ends by the root's real mouse-up.
 if not heldOk and P._panelDrag then local up=root:GetScript('OnMouseUp');if up then pcall(up,root) end end
 if not heldOk then error(heldErr,0) end
end)

C.scenario('C4 a failing render still hides the root, keeps it hidden and ends a move once',function()
 -- Held-Shift scope for this real move (as in C3), through the failing
 -- render, its cleanup and the recovery render.
 local shiftBefore=IsShiftKeyDown
 IsShiftKeyDown=function() return 1 end
 local heldOk,heldErr=pcall(function()
 ResetMove()
 local build=root._contextBuildHit
 build:GetScript('OnDragStart')(build,'LeftButton')
 Move.x=420
 local header=rawget(P,'UpdateContextHeader')
 rawset(P,'UpdateContextHeader',function() error('synthetic header failure') end)
 local ok=pcall(P.Render,Model({wishlist='Fails'}))
 rawset(P,'UpdateContextHeader',header)
 C.guard(not ok and not root:IsShown(),'C4: the failing render leaves the root hidden')
 C.guard(P._panelDrag==nil and Move.stops==1 and Saved()==420-960,'C4: the move ended once and saved its position once',Move.stops)
 C.guard(P.Render(Model())==true and root:IsShown(),'C4: the next good render shows the panel again')
 end)
 IsShiftKeyDown=shiftBefore
 -- Cleanup only after an error: a move left active ends by the root's real mouse-up.
 if not heldOk and P._panelDrag then local up=root:GetScript('OnMouseUp');if up then pcall(up,root) end end
 if not heldOk then error(heldErr,0) end
end)

C.scenario('C5 a hidden panel stays hidden through renders; a first render shows it after its commit',function()
 P.Hide()
 C.setup(not root:IsShown(),'C5: fixture: the player hid the panel')
 P.Render(Model())
 C.guard(not root:IsShown(),'C5: a render keeps the player\'s hide')
 P.Show()
 C.guard(root:IsShown(),'C5: the player\'s show brings it back')
 local shownDuring
 local header=rawget(P,'UpdateContextHeader')
 root:Hide()
 rawset(P,'UpdateContextHeader',function(...) shownDuring=root:IsShown();return header(...) end)
 local ok=P.Render(Model({wishlist='Reopened'}))
 rawset(P,'UpdateContextHeader',header)
 C.guard(ok==true and shownDuring==false and root:IsShown(),'C5: a hidden panel is not shown while it applies, then shown after its commit',
  tostring(shownDuring))
 P.Render(Model())
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(source invariant and an input-loss model; native pointer capture, drag threshold, focus and hit order NOT RUN)')
