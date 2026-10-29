-- Issue #168: plain-left dragging of the main panel from its background and
-- every passive label, count, card and icon, with hover areas that fit the
-- text a label shows. One owner moves the panel: the root and each passive
-- surface start and finish the same move of the root (one StartMoving, one
-- StopMovingOrSizing), and its position is saved once, only after it moved
-- and only from valid reads, in UIParent units.
-- R1 every passive surface on the rendered panel (background, grip, title,
--    Build and Wishlist lines, Details counts, best-known label, Orb line,
--    offer card, Callboard icon, title and objective) moves the same root
--    with a plain left drag, and the move saves panelX / panelY once;
-- R2 a plain click saves nothing and moves nothing; a right drag does not
--    start; a second start while one is active is refused and keeps the
--    first origin;
-- R3 the counts that open the Wishlist Editor, the difficulty line and the
--    panel's buttons are not drag surfaces and keep their own action;
-- R4 release, mouse-up and hide in any order finish once; the root's hide
--    and the origin's hide end the move, another label's hide does not;
-- R5 a failing or invalid position read after the move is stopped saves
--    nothing, leaves no active move, and the next drag still works;
-- R6 the saved offset is in UIParent units at a scaled panel;
-- R7 hover areas fit their text: short Build / Wishlist text leaves the rest
--    of the row to the background, a shortened name keeps the whole box and
--    its complete text, an empty label takes no mouse, right and centred
--    text fit from their own edge;
-- R8 a Details toggle while a move is active does not re-anchor the panel,
--    and Details growth never writes panelX / panelY.
-- Categories (view_regression_support): EXPECT is behaviour this change adds
-- (fails at c7e4d7cd: labels have no drag forwarding, the grip needs Shift,
-- hovers cover their whole row), GUARD already held, SETUP is the fixture.
-- Native seams spied: the root's StartMoving / StopMovingOrSizing and its
-- centre / scale reads (the harness has no layout engine). The real Panel
-- handlers run. Native pointer capture, drag threshold and hit order are
-- NOT RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('crimson_panel_drag')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local P=Nexus.Panel
local RM=G.RegionMethods()
-- Observation only: mouse and justification state the harness does not keep.
RM.EnableMouse=function(self,v) self._mouse=v and true or false end
RM.IsMouseEnabled=function(self) return self._mouse==true end
RM.SetJustifyH=function(self,v) self._justify=v end
RM.GetJustifyH=function(self) return self._justify or 'LEFT' end
RM.RegisterForDrag=function(self,...) self._dragButtons={...} end

-- Synthetic Callboard objective (another module's data).
local board={observed=true,title='Ember Watch',lines={'Light 4 braziers','Guard the Ember Gate'},rewards={}}
Nexus.CallboardStatus.GetSummary=function() return board end

local function Model(o)
 o=o or {}
 return {status='ready',level=o.level or 40,auto=false,cards=o.cards or {},recommendation=o.recommendation or '',
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
C.setup(P.Render(Model({cards={{text='Frostwake Sigil (Rare)'}}}))==true and NexusPanel:IsShown(),'fixture: the panel renders')
local root=NexusPanel

-- The native move: StartMoving / StopMovingOrSizing on the root are counted,
-- and the root's centre and effective scale are what the test sets.
local Move={starts=0,stops=0,x=400,y=300,scale=1,others=0}
rawset(root,'StartMoving',function(self) if self==root then Move.starts=Move.starts+1 else Move.others=Move.others+1 end end)
rawset(root,'StopMovingOrSizing',function(self) Move.stops=Move.stops+1 end)
rawset(root,'GetCenter',function() if Move.centerFails then error('centre read failed') end return Move.x,Move.y end)
rawset(root,'GetEffectiveScale',function() return Move.scale end)
rawset(UIParent,'GetCenter',function() return 960,540 end)
-- Every other frame that StartMoving reaches is counted as a wrong target.
RM.StartMoving=function() Move.others=Move.others+1 end
local function Saved() local s=P.SavedLayoutRoot();return s.panelX,s.panelY end
local function ClearSaved() local s=P.SavedLayoutRoot();s.panelX,s.panelY=nil,nil end
local function Reset() Move.starts,Move.stops,Move.others=0,0,0;Move.x,Move.y=400,300;Move.scale=1;Move.centerFails=nil end

-- A plain left drag from `hit` that moves the panel by (dx,dy).
local function DragFrom(hit,dx,dy)
 local start=hit:GetScript('OnDragStart')
 if not start then return false end
 start(hit,'LeftButton')
 Move.x,Move.y=Move.x+(dx or 30),Move.y+(dy or -20)
 local stop=hit:GetScript('OnDragStop')
 if stop then stop(hit) end
 return true
end

local function Surfaces()
 local p=root._play or {}
 local cb=root._offerCards and root._offerCards[1]
 return {
  {'the background',root},{'the grip',root._dragGrip},{'the title',root._contextTitleHit},
  {'the Build line',root._contextBuildHit},{'the Wishlist line',root._contextWishlistHit},
  {'the Missing tomes count',p.tomesHit},{'the Extra copies count',p.extraHit},
  {'the best-known label',p.bestHit},{'the offer card',cb},
  {'the Callboard icon',root._callboardIcon},{'the Callboard title',root._callboardTitleHit},
  {'the Callboard objective',root._callboardLineHit},
 }
end

C.scenario('R1 every passive surface moves the same root with a plain left drag and saves once',function()
 local before=Effects()
 if not P._playDetails then P.TogglePlanDetails() end
 P.Render(Model({cards={{text='Frostwake Sigil (Rare)'}}}))
 for _,s in ipairs(Surfaces()) do
  local name,hit=s[1],s[2]
  if C.setup(hit~=nil and hit:IsShown(),'R1: fixture: '..name..' is shown') then
   Reset();ClearSaved()
   C.expect(DragFrom(hit,30,-20),'R1: '..name..' has a drag start')
   local x,y=Saved()
   C.expect(Move.starts==1 and Move.stops==1 and Move.others==0,
    'R1: a plain left drag from '..name..' moves the panel root once and stops it',Move.starts..'/'..Move.stops..'/'..Move.others)
   C.expect(x==-530 and y==-260,'R1: the move from '..name..' saves the new centre offset',tostring(x)..','..tostring(y))
   C.expect(P._panelDrag==nil,'R1: no move stays active after '..name)
  end
 end
 C.guard(Effects()==before,'R1: moving the panel changes no action, send or Auto',Effects())
end)

C.scenario('R2 a click saves nothing; a right drag does not start; a second start is refused',function()
 local build=root._contextBuildHit
 Reset();ClearSaved()
 C.expect(build:GetScript('OnMouseUp')==nil and build:GetScript('OnClick')==nil,
  'R2: a passive label gets no click or mouse-up script')
 local rootUp=root:GetScript('OnMouseUp')
 if rootUp then rootUp(root,'LeftButton') end
 C.expect(Move.starts==0 and Move.stops==0 and Saved()==nil,'R2: a plain click on a label or the background moves and saves nothing')
 local start=build:GetScript('OnDragStart')
 if C.setup(start~=nil,'R2: fixture: the Build line has a drag start') then
  start(build,'RightButton')
  C.expect(Move.starts==0 and P._panelDrag==nil,'R2: a right drag does not start a move')
  C.expect(type(build._dragButtons)=='table' and build._dragButtons[1]=='LeftButton' and #build._dragButtons==1,
   'R2: the label registers only the left button for dragging')
  start(build,'LeftButton')
  local wish=root._contextWishlistHit
  wish:GetScript('OnDragStart')(wish,'LeftButton')
  C.expect(Move.starts==1 and P._panelDrag and P._panelDrag.origin==build,
   'R2: a second start while a move is active is refused and keeps the first origin',Move.starts)
  build:GetScript('OnDragStop')(build)
  C.expect(Move.stops==1 and P._panelDrag==nil,'R2: its release ends the one move')
 end
end)

C.scenario('R3 counts that open the editor, the difficulty line and buttons keep their own input',function()
 local p=root._play
 local opened=0
 local editor=Nexus.WishlistEditor
 local show=editor and editor.Show
 if editor then editor.Show=function() opened=opened+1 end end
 local excluded={{'the Still needed count',p and p.neededHit},{'the Locked targets count',p and p.lockedHit},
  {'the difficulty line',p and p.serverHit},{'Auto',root._autoBtn},{'Options',root._menuBtn},{'Close',root._closeBtn},
  {'My Builds',root._switchBtn},{'Change',root._contextChange},{'Details',p and p.details},{'Orb Open',p and p.orbOpen}}
 for _,e in ipairs(excluded) do
  local name,hit=e[1],e[2]
  if hit then
   C.expect(hit:GetScript('OnDragStart')==nil and not hit._nexusPassiveDrag,'R3: '..name..' is not a drag surface')
  end
 end
 if p and p.neededHit then
  p.neededHit:GetScript('OnMouseUp')(p.neededHit,'LeftButton')
  p.lockedHit:GetScript('OnMouseUp')(p.lockedHit,'LeftButton')
  C.guard(opened==2,'R3: the Still needed and Locked targets counts still open the Wishlist Editor',opened)
 end
 if editor then editor.Show=show end
 C.guard(type(root._menuBtn:GetScript('OnClick'))=='function' and type(root._contextChange:GetScript('OnClick'))=='function',
  'R3: Options and Change keep their click')
end)

C.scenario('R4 release, root mouse-up and hide finish once; root and origin hide end the move, another label does not',function()
 local build,wish=root._contextBuildHit,root._contextWishlistHit
 Reset();ClearSaved()
 build:GetScript('OnDragStart')(build,'LeftButton')
 Move.x,Move.y=450,330
 build:GetScript('OnDragStop')(build)
 local x1,y1=Saved()
 Move.x,Move.y=10,10
 root:GetScript('OnMouseUp')(root,'LeftButton')
 root:Hide();root:Show()
 local x2,y2=Saved()
 C.expect(x1==-510 and y1==-210 and x2==x1 and y2==y1 and Move.stops==1,
  'R4: a release, then a mouse-up and a hide of the root, save once and stop once',tostring(x2)..','..tostring(y2)..' stops='..Move.stops)
 Reset();ClearSaved()
 build:GetScript('OnDragStart')(build,'LeftButton')
 wish:Hide()
 C.expect(P._panelDrag~=nil and Move.stops==0,'R4: another label hiding does not end the move')
 wish:Show()
 Move.x=420
 build:Hide()
 C.expect(P._panelDrag==nil and Move.stops==1 and Saved()==-540,'R4: the origin hiding ends the move and saves where it is',tostring(Saved()))
 build:Show()
 Reset();ClearSaved()
 wish:GetScript('OnDragStart')(wish,'LeftButton')
 Move.y=310
 root:Hide()
 local _,y=Saved()
 C.expect(P._panelDrag==nil and Move.stops==1 and y==-230,'R4: the panel hiding (menu suppression) ends the move',tostring(y))
 root:Show()
 Reset()
 C.expect(DragFrom(root._contextTitleHit) and Move.starts==1 and Move.stops==1,'R4: a later drag still works')
end)

C.scenario('R5 a failing or invalid position read saves nothing and leaves the next drag usable',function()
 local build=root._contextBuildHit
 for _,case in ipairs({{'a failing centre read',function() Move.centerFails=true end},
  {'a NaN centre',function() Move.x=0/0 end},{'an infinite centre',function() Move.y=math.huge end},
  {'a zero scale',function() Move.scale=0 end}}) do
  Reset();ClearSaved()
  build:GetScript('OnDragStart')(build,'LeftButton')
  case[2]()
  local ok=pcall(build:GetScript('OnDragStop'),build)
  C.expect(ok and Move.stops==1 and P._panelDrag==nil and Saved()==nil,
   'R5: '..case[1]..' after the stop saves nothing and leaves no active move')
 end
 Reset();ClearSaved()
 C.expect(DragFrom(build,10,10) and Saved()==-550,'R5: the next drag saves again',tostring(Saved()))
 Reset();ClearSaved()
 build:GetScript('OnDragStart')(build,'LeftButton')
 build:GetScript('OnDragStop')(build)
 C.expect(Move.stops==1 and Saved()==nil,'R5: a drag that ends where it began writes nothing')
end)

C.scenario('R6 the saved offset is in UIParent units at a scaled panel',function()
 Reset();ClearSaved()
 Move.scale=0.5
 -- At half scale the root's own centre (800,600) is (400,300) in UIParent units.
 local build=root._contextBuildHit
 build:GetScript('OnDragStart')(build,'LeftButton')
 Move.x,Move.y=800,600
 build:GetScript('OnDragStop')(build)
 local x,y=Saved()
 C.expect(x==-560 and y==-240,'R6: the centre is converted through both effective scales',tostring(x)..','..tostring(y))
end)

C.scenario('R7 hover areas fit the text each label shows',function()
 G.UseFont(G.MODELS.default)
 P.Render(Model({wishlist='Ash'}))
 local wishText,wish=root._contextWishlist,root._contextWishlistHit
 local lr,hr=G.Rect(wishText,root),G.Rect(wish,root)
 local textW=G.Length(G.Visible(wishText:GetText()))*G.MODELS.default.char
 C.expect(hr[1]==lr[1] and hr[2]==lr[2] and hr[4]==lr[4] and hr[3]-hr[1]<lr[3]-lr[1]
  and hr[3]-hr[1]>=textW and hr[3]-hr[1]<=textW+4,
  'R7: the short Wishlist line\'s hover covers its text and pad, not the rest of the row',G.Text(hr)..' in '..G.Text(lr))
 C.expect(lr[3]-hr[3]>=50,'R7: at least 50 px of the row beside it is left to the background drag',lr[3]-hr[3])
 local long='Wishlist '..string.rep('Long Name ',20)
 P.Render(Model({wishlist=long}))
 lr,hr=G.Rect(wishText,root),G.Rect(wish,root)
 C.expect(hr[1]==lr[1] and hr[3]==lr[3],'R7: a shortened Wishlist name keeps the whole visible box',G.Text(hr)..' in '..G.Text(lr))
 local tip=table.concat(V.TooltipLines(wish:GetScript('OnEnter'),wish),' ')
 C.guard(tip:find('Long Name Long Name Long Name',1,true)~=nil,'R7: its hover still shows the complete name',tip)
 local cbText,cbHit=root._callboardLine,root._callboardLineHit
 if C.setup(cbHit:IsShown(),'R7: fixture: the Callboard objective is shown') then
  local cr,ch=G.Rect(cbText,root),G.Rect(cbHit,root)
  C.expect(ch[1]==cr[1] and ch[3]<cr[3],'R7: the objective hover ends with its text',G.Text(ch)..' in '..G.Text(cr))
 end
 -- Right and centred labels fit from their own edge; an empty label takes no mouse.
 local fs=root:CreateFontString()
 local hit=CreateFrame('Frame',nil,root)
 fs:SetPoint('TOPLEFT',root,'TOPLEFT',20,-100);fs:SetSize(200,14);fs:SetText('Twelve chars')
 hit:EnableMouse(true)
 fs:SetJustifyH('RIGHT');P.FitPassiveHover(hit,fs)
 local r,h=G.Rect(fs,root),G.Rect(hit,root)
 C.expect(h[3]==r[3] and h[3]-h[1]==70,'R7: a right-justified label\'s hover ends at its right edge',G.Text(h))
 fs:SetJustifyH('CENTER');P.FitPassiveHover(hit,fs)
 h=G.Rect(hit,root)
 C.expect(math.abs((h[1]+h[3])/2-(r[1]+r[3])/2)<0.01 and h[3]-h[1]==74,'R7: a centred label\'s hover is centred on it',G.Text(h))
 fs:SetText('');P.FitPassiveHover(hit,fs)
 C.expect(hit:IsMouseEnabled()==false,'R7: an empty label takes no mouse')
 fs:SetText('Back');P.FitPassiveHover(hit,fs)
 C.expect(hit:IsMouseEnabled()==true,'R7: with text again it takes the mouse again')
end)

C.scenario('R8 a Details toggle during a move does not re-anchor; Details growth writes no position',function()
 P.Render(Model())
 Reset();ClearSaved()
 local build=root._contextBuildHit
 build:GetScript('OnDragStart')(build,'LeftButton')
 local anchored=0
 local clear=rawget(root,'ClearAllPoints')
 rawset(root,'ClearAllPoints',function(self) anchored=anchored+1;return RM.ClearAllPoints(self) end)
 P.TogglePlanDetails()
 P.Render(Model())
 C.expect(anchored==0,'R8: a Details toggle and render while a move is active do not re-anchor the panel',anchored)
 C.expect(P._panelDrag~=nil and Move.stops==0,'R8: the render hiding and showing the panel in one call does not end the move')
 build:GetScript('OnDragStop')(build)
 ClearSaved()
 P.TogglePlanDetails()
 P.Render(Model())
 P.TogglePlanDetails()
 P.Render(Model())
 rawset(root,'ClearAllPoints',clear)
 C.guard(Saved()==nil,'R8: Details growth and collapse write no panelX / panelY')
end)

Nexus.DisableOrdinaryAutomation()
C.finish('(main panel drag owner and passive hover geometry over the harness; native pointer capture, threshold and hit order NOT RUN)')
