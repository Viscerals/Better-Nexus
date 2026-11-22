-- Issue #168 with the requested Shift gate: left dragging of the main panel
-- while Shift is held, from its background, its grip and every passive
-- label, count, card and icon, with hover areas that fit the text a label
-- shows. One owner moves the panel: the root and each passive surface start
-- and finish the same move of the root (one StartMoving, one
-- StopMovingOrSizing), and its position is saved once, only after it moved
-- and only from valid reads, in UIParent units.
-- R1 every passive surface on the rendered panel (background, grip, title,
--    Build and Wishlist lines, Details counts, best-known label, Orb line,
--    offer card, Callboard icon, title and objective) moves the same root
--    with a left drag while Shift is held, and the move saves panelX /
--    panelY once;
-- R2 a plain click saves nothing and moves nothing; with Shift held a right
--    drag does not start, and a second start while one is active is refused
--    and keeps the first origin;
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
-- SHIFT-01 a left drag start from the root, the grip or a passive surface
--    begins only while IsShiftKeyDown() answers 1 or true; nil, false, 0, a
--    string, a failing read or a missing API refuses it without a Lua error:
--    nothing moves, nothing is saved, no move stays active. Shift released
--    during a move, the offer slot and help text are later slices, not here.
-- Every older drag scenario runs with Shift held (Reset), so its non-left
-- and one-owner refusals cannot pass merely because no modifier is down; a
-- held-Shift pass there is a compatibility guard, not native evidence.
-- Categories (view_regression_support): EXPECT is behaviour a change adds
-- (#168 failed at c7e4d7cd: labels had no drag forwarding, the grip needed
-- Shift, hovers covered their whole row; SHIFT-01's refusals are expected to
-- fail against the current Panel, whose M.BeginPanelDrag reads no
-- modifier), GUARD already held, SETUP is the fixture. IsShiftKeyDown is a
-- controlled test seam here, restored before the final cleanup.
-- Native seams spied: the root's StartMoving / StopMovingOrSizing and its
-- centre / scale reads (the harness has no layout engine). The real Panel
-- handlers run. Native pointer capture, drag threshold and hit order are
-- NOT RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('crimson_panel_drag')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
-- SHIFT-01 seam: the Shift state a drag start reads (held, as the client's 1,
-- after Reset). A scenario may set another answer, a failing read, or remove
-- the API; Reset puts the seam back. The original returns before cleanup.
local RealIsShiftKeyDown=IsShiftKeyDown
local Shift={value=1}
local function ShiftSeam() if Shift.fails then error('Shift read failed') end return Shift.value end
IsShiftKeyDown=ShiftSeam
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
  -- (v12: only R7's short-name render gives one; every other model is as it was.)
  assignment=o.assignment,
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
local function Reset() Move.starts,Move.stops,Move.others=0,0,0;Move.x,Move.y=400,300;Move.scale=1;Move.centerFails=nil;Shift.value,Shift.fails=1,nil;IsShiftKeyDown=ShiftSeam end

-- A left drag from `hit` with Shift as the seam answers (held after Reset) that moves the panel by (dx,dy).
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
 -- Approved panel cleanup: a DPS entry exists only for a record that exists
 -- (play_panel_summary S4b / S4c), so this fixture carries both records to
 -- have the best-known surface to drag from.
 local shown=Model({cards={{text='Frostwake Sigil (Rare)'}}})
 shown.bestDps={dummy={dps=4812}}
 shown.progress.performance={dummy={global={dps=5130,player='Synthetic'}},lk={}}
 P.Render(shown)
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
 -- v12 (Root's focused run: "at least 50 px of the row beside it is left to
 -- the background drag [5]"). That figure was read inside the Wishlist
 -- text's own box, lr[3]-hr[3], and belonged to the 420-unit row: this
 -- model states no assignment, so the line reads "Ash (assignment not
 -- known)", 26 characters, 143 units in this font model, in a value column
 -- that the approved 284-unit row makes 152 units wide; the text-sized hover
 -- (asked above, and held) leaves 5 of them. Nothing about the hover
 -- changed: the row is narrower and these words nearly fill their column.
 -- What the figure stood for is asked of the row itself, in two parts.
 -- (1) On this row as it is, the room beside the text is the background's:
 -- from the hover's right edge to the row's own button (Change) there is
 -- room, the text's box ends the draft's 6 pixels before that button
 -- (4 units at this text size: 6 x 284 / 420 rounded), so the room is
 -- exactly what the text leaves of its box plus that gap, and no other
 -- passive surface of the panel (Surfaces, the list R1 drags from) reaches
 -- into it: a drag started there starts on the root.
 -- (2) A short text leaves at least the 50 units the check asked for: with
 -- the Wishlist stated as assigned the approved line shows its name alone,
 -- "Ash", and the same text-sized hover then leaves the rest of the column.
 -- EXPECT: "lr[3]-hr[3]>=50" on the first render.
 local change=G.Rect(root._contextChange,root)
 local gap=math.max(1,math.floor(6*284/420+0.5))
 local room={hr[3],lr[2],change[1],lr[4]}
 local taken={}
 for _,surface in ipairs(Surfaces()) do
  local hit=surface[2]
  if hit and hit~=root and hit~=wish and hit:IsVisible() then
   local ok,r=pcall(G.Rect,hit,root)
   if ok and r and not G.Apart(r,room) then taken[#taken+1]=surface[1] end
  end
 end
 C.expect(change[1]-lr[3]==gap and room[3]-room[1]==(lr[3]-lr[1])-(hr[3]-hr[1])+gap and room[3]>room[1]
  and G.Inside(room,{0,0,root:GetWidth(),root:GetHeight()}) and #taken==0,
  'R7: the room beside the Wishlist text, up to the row\'s button, is what the text leaves of its box and the draft\'s 6-pixel gap, and only the background takes a drag there',
  string.format('%.1f beside %s, button %s, taken by [%s]',room[3]-room[1],G.Text(hr),G.Text(change),table.concat(taken,', ')))
 P.Render(Model({wishlist='Ash',assignment={state='ready',name='Ash'}}))
 lr,hr=G.Rect(wishText,root),G.Rect(wish,root)
 if C.setup(G.Visible(wishText:GetText())=='Ash','R7: fixture: a Wishlist stated as assigned shows its name alone',wishText:GetText()) then
  C.expect(hr[1]==lr[1] and hr[3]-hr[1]<=3*G.MODELS.default.char+4 and lr[3]-hr[3]>=50,
   'R7: at least 50 px of the row beside it is left to the background drag',lr[3]-hr[3])
 end
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

C.scenario('SHIFT-01 a drag starts only while Shift answers 1 or true; any other answer refuses it',function()
 local before=Effects()
 P.Render(Model())
 local build=root._contextBuildHit
 local surfaces={{'the background',root},{'the grip',root._dragGrip},{'the Build line',build}}
 local held={{'numeric 1',1},{'boolean true',true}}
 local refused={{'nil',function() Shift.value=nil end},{'false',function() Shift.value=false end},
  {'numeric 0',function() Shift.value=0 end},{'a string',function() Shift.value='1' end},
  {'a failing read',function() Shift.fails=true end},{'a missing API',function() IsShiftKeyDown=nil end}}
 for _,s in ipairs(surfaces) do
  local name,hit=s[1],s[2]
  if C.setup(hit~=nil and hit:IsShown() and hit:GetScript('OnDragStart')~=nil,'SHIFT-01: fixture: '..name..' is shown with a drag start') then
   for _,v in ipairs(held) do
    Reset();ClearSaved()
    Shift.value=v[2]
    DragFrom(hit,30,-20)
    local x,y=Saved()
    C.guard(Move.starts==1 and Move.stops==1 and Move.others==0 and x==-530 and y==-260 and P._panelDrag==nil,
     'SHIFT-01: Shift held as '..v[1]..' lets a left drag from '..name..' move the root once and save once',
     Move.starts..'/'..Move.stops..'/'..Move.others..' '..tostring(x)..','..tostring(y))
   end
   for _,v in ipairs(refused) do
    Reset();ClearSaved()
    v[2]()
    local ok=pcall(DragFrom,hit,30,-20)
    IsShiftKeyDown=ShiftSeam;Shift.fails=nil
    local x,y=Saved()
    C.expect(ok and Move.starts==0 and Move.others==0 and P._panelDrag==nil and x==nil and y==nil,
     'SHIFT-01: Shift answering '..v[1]..' refuses a left drag from '..name..': nothing moves or saves',
     tostring(ok)..' '..Move.starts..'/'..Move.others..' '..tostring(x)..','..tostring(y))
    if P._panelDrag then P.FinishPanelDrag() end
    ClearSaved()
   end
  end
 end
 -- One owner with Shift held: background and grip starts are refused while a move is active.
 Reset();ClearSaved()
 build:GetScript('OnDragStart')(build,'LeftButton')
 for _,s in ipairs(surfaces) do
  local start=s[2] and s[2]~=build and s[2]:GetScript('OnDragStart')
  if start then start(s[2],'LeftButton') end
 end
 C.guard(Move.starts==1 and P._panelDrag~=nil and P._panelDrag.origin==build,
  'SHIFT-01: with Shift held, a background or grip start during a move is refused and keeps the first origin',Move.starts)
 build:GetScript('OnDragStop')(build)
 C.guard(Move.stops==1 and P._panelDrag==nil,'SHIFT-01: its release ends the one move')
 Reset();ClearSaved()
 C.guard(Effects()==before,'SHIFT-01: refused and accepted starts change no action, send or Auto',Effects())
end)

-- SHIFT-02 an active move whose Shift is no longer held (nil, false, 0, a
-- string, a failing read or a missing API) ends on the next host tick: the
-- root stops once, the moved finite offset is saved once, no move stays
-- active; later ticks, its drag-stop, the root's mouse-up and a hide stop,
-- save or move nothing more. While Shift stays held, ticks change nothing.
-- No motion or an invalid centre read at that end saves nothing. Ticks are
-- H.Advance frame dispatch only (bounded .05 s steps): native pointer
-- capture, release timing and any automatic native stop are NOT RUN.
C.scenario('SHIFT-02 an active move ends once when Shift stops answering 1 or true',function()
 local before=Effects()
 P.Render(Model())
 local build=root._contextBuildHit
 local bg,grip,bl={'the background',root},{'the grip',root._dragGrip},{'the Build line',build}
 -- Bounded host dispatch; a raised error is a failure, never a refusal or a finish.
 local function Tick(n)
  for _=1,n do
   local ok,err=pcall(H.Advance,.05,.05)
   if not ok then return false,tostring(err) end
  end
  return true,''
 end
 local function State(ok,err)
  local x,y=Saved()
  return tostring(ok)..' '..Move.starts..'/'..Move.stops..'/'..Move.others..' active='..tostring(P._panelDrag~=nil)
   ..' saved='..tostring(x)..','..tostring(y)..' '..(err or '')
 end
 -- Cleanup only, never counted as a release: a move this source left active
 -- is ended by the surface's real drag-stop, then the root's real mouse-up.
 local function EndLeftover(hit)
  if not P._panelDrag then return end
  Shift.value,Shift.fails=1,nil;IsShiftKeyDown=ShiftSeam
  local stop=hit and hit:GetScript('OnDragStop')
  if stop then pcall(stop,hit) end
  local up=root:GetScript('OnMouseUp')
  if P._panelDrag and up then pcall(up,root,'LeftButton') end
  if P._panelDrag then P.FinishPanelDrag() end
 end
 local function Begin(s,held)
  Reset();ClearSaved()
  Shift.value=held
  local start=s[2] and s[2]:GetScript('OnDragStart')
  if start then start(s[2],'LeftButton') end
  return C.setup(P._panelDrag~=nil and Move.starts==1,'SHIFT-02: fixture: a left drag from '..s[1]..' with Shift held as '..tostring(held)..' is active')
 end
 -- Held: ticks keep the same move; its real release saves once; a later tick without Shift adds nothing.
 for _,c in ipairs({{bg,1},{bg,true},{grip,1},{grip,true},{bl,1},{bl,true}}) do
  local s,held=c[1],c[2]
  if Begin(s,held) then
   local owner=P._panelDrag
   Move.x,Move.y=430,280
   local ok,err=Tick(2)
   C.guard(ok and P._panelDrag==owner and Move.stops==0 and Saved()==nil,
    'SHIFT-02: while Shift stays held as '..tostring(held)..', host ticks keep the move from '..s[1]..' active and save nothing',State(ok,err))
   local okStop=pcall(s[2]:GetScript('OnDragStop'),s[2])
   local x,y=Saved()
   Shift.value=nil
   local okAfter,errAfter=Tick(1)
   local x2,y2=Saved()
   C.guard(okStop and okAfter and P._panelDrag==nil and Move.stops==1 and x==-530 and y==-260 and x2==x and y2==y,
    'SHIFT-02: its real release from '..s[1]..' stops and saves once; a later tick without Shift stops and saves nothing more',
    State(okAfter,errAfter)..' stop='..tostring(okStop))
  end
  EndLeftover(s[2])
 end
 -- Lost during motion: the next tick ends the move once and keeps the moved offset.
 local lost={
  {bg,1,'nil',function() Shift.value=nil end},
  {grip,true,'false',function() Shift.value=false end},
  {bl,1,'numeric 0',function() Shift.value=0 end},
  {bg,true,'a string',function() Shift.value='1' end},
  {grip,1,'a failing read',function() Shift.fails=true end},
  {bl,true,'a missing API',function() IsShiftKeyDown=nil end},
 }
 for _,c in ipairs(lost) do
  local s,held,name,lose=c[1],c[2],c[3],c[4]
  if Begin(s,held) then
   Move.x,Move.y=430,280
   lose()
   local ok,err=Tick(1)
   local x,y=Saved()
   local released=ok and P._panelDrag==nil and Move.stops==1 and x==-530 and y==-260
   C.expect(released,'SHIFT-02: Shift answering '..name..' during a move from '..s[1]..' ends it on the next host tick, stops once and saves the moved offset',State(ok,err))
   local later,detail=false,'not reached: the tick did not end the move'
   if released then
    Move.x,Move.y=10,10
    local okT,errT=Tick(2)
    local okStop=pcall(s[2]:GetScript('OnDragStop'),s[2])
    local okUp=pcall(root:GetScript('OnMouseUp'),root,'LeftButton')
    local okHide=pcall(function() s[2]:Hide();s[2]:Show() end)
    local x2,y2=Saved()
    later=okT and okStop and okUp and okHide and P._panelDrag==nil and Move.starts==1 and Move.stops==1 and Move.others==0 and x2==x and y2==y
    detail=State(okT,errT)..' stop='..tostring(okStop)..' up='..tostring(okUp)..' hide='..tostring(okHide)
   end
   C.expect(later,'SHIFT-02: after that end, more ticks, its drag-stop, the root mouse-up and a hide of '..s[1]..' stop, save or move nothing more',detail)
  end
  EndLeftover(s[2])
 end
 -- No motion or an invalid centre at that end: one stop, no position written.
 local quiet={
  {bl,1,'no motion',function() end},
  {grip,true,'a failing centre read',function() Move.x=430;Move.centerFails=true end},
  {bg,1,'a NaN centre',function() Move.x=0/0 end},
 }
 for _,c in ipairs(quiet) do
  local s,held,name,arrange=c[1],c[2],c[3],c[4]
  if Begin(s,held) then
   arrange()
   Shift.value=false
   local ok,err=Tick(1)
   C.expect(ok and P._panelDrag==nil and Move.stops==1 and Saved()==nil,
    'SHIFT-02: Shift lost during a move from '..s[1]..' with '..name..' ends it once and saves no position',State(ok,err))
  end
  EndLeftover(s[2])
 end
 Reset();ClearSaved()
 local okD=DragFrom(build,30,-20)
 local x,y=Saved()
 C.guard(okD and Move.starts==1 and Move.stops==1 and x==-530 and y==-260 and P._panelDrag==nil,
  'SHIFT-02: a later held drag still moves and saves once',State(okD))
 Reset();ClearSaved()
 C.guard(Effects()==before and before:find('auto=false',1,true)~=nil,'SHIFT-02: Auto stays off and no action or send changes',before..' -> '..Effects())
end)

-- SHIFT-02 cleanup: no move stays active and the seam is held again before the original seam cleanup.
if P._panelDrag then P.FinishPanelDrag() end
Reset();ClearSaved()

-- SHIFT-01 seam cleanup: the harness's own IsShiftKeyDown returns before the final cleanup.
IsShiftKeyDown=RealIsShiftKeyDown

Nexus.DisableOrdinaryAutomation()
C.finish('(main panel drag owner and passive hover geometry over the harness; native pointer capture, threshold and hit order NOT RUN)')
