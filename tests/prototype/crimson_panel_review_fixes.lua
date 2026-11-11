-- Independent review corrections for the main panel (issues #168, #170,
-- #171, #169), each through the real Panel handlers and controls:
-- V1 (#168, D11) while a move is active, a render's own hide-and-show of the
--    panel does not end it or write a position, even when the hide reaches
--    the shown descendants (the drag origin among them); a real hide of the
--    panel, or the origin's removal by a render, still ends it and saves
--    once; another label disappearing does not;
-- V2 (#168) the visible passive hovers the earlier fit missed (Charges, the
--    recommendation, the Details headings and Extra copies list) fit the text
--    they show, from their own edge, after a font change too; a shortened
--    or overflowing text keeps its whole box; the hidden destination row
--    takes no input;
-- V3 (#168) during a move, hovering the Callboard title (shortened, so its
--    complete-text hover would open) or the objective leaves no tooltip of
--    theirs open; without a move both still show their complete text; a
--    tooltip another frame owns stays open;
-- V4 (#170) a centre saved while the chosen size is reduced to fit is where
--    the panel is placed after a fresh load at that fitted size;
-- V5 (#170) the public FitToScreen refuses infinite frame or screen sizes
--    (and keeps the panel's scale) instead of exceeding the ceiling;
-- V6 (#171) after a confirmed pause, a Status that fails or is malformed is
--    shown as unknown, never as "nothing is paused" or as paused;
-- V7 (#171, #169) with a committed model of Auto selected ON and ready, a
--    confirmed pause through the Options row makes the Auto hover and the
--    details say the session pause holds it (no "Now: ready"); Resume runs
--    no refresh step and restores the model's own state words;
-- V8 (#168, re-review of 6f9d04f) a render that hides the drag origin's
--    parent (the roll area of a board without an offer) ends the move once,
--    saving only movement, though the origin's own shown flag stays set;
-- V9 (#171, #169, re-review of 6f9d04f) Auto selected ON and ready, then a
--    confirmed Pause, then a Status that fails or is malformed: the hover and
--    the details say the state is unknown, never "Now: ready" or paused.
-- Native seams modelled by the test, not client proof: the propagation of a
-- hide to shown descendants (as the client documents for OnHide), effective
-- scale as the product of own scales, the root's centre and corner reads,
-- the shared tooltip's owner, and UIParent's size. Nexus.SessionPause is a
-- boundary double of its frozen API. Categories (view_regression_support):
-- EXPECT fails at 4358349 (V1-V7) and 6f9d04f (V8, V9) by design, GUARD
-- already held, SETUP is the
-- fixture. Native NOT RUN.
local F=dofile('tests/prototype/format5_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local G=dofile('tests/prototype/layout_geometry_support.lua')
local C=V.Checker('crimson_panel_review_fixes')

local H=F.Boot(F.Database(),function(h) F.OrbService(h) end)
local P,LM=Nexus.Panel,Nexus.LayoutMetrics
local RM=G.RegionMethods()
RM.EnableMouse=function(self,v) self._mouse=v and true or false end
RM.IsMouseEnabled=function(self) return self._mouse==true end
RM.SetJustifyH=function(self,v) self._justify=v end
RM.GetJustifyH=function(self) return self._justify or 'LEFT' end
RM.GetEffectiveScale=function(self)
 local parent=self.parent
 return (self.scale or 1)*(parent and parent.GetEffectiveScale and parent:GetEffectiveScale() or 1)
end
-- REG-SLOT (MI-F01) observation, installed before the first render: the
-- numeric colour each region receives through SetTexture(r,g,b[,a]) or
-- SetVertexColor(r,g,b[,a]), and a path or lone numeric id given to
-- SetTexture, are recorded per region instance; every call then goes on
-- unchanged (same arguments, results and errors) to the method the harness
-- had, or does nothing where it had none (its no-op). Nothing is created,
-- placed or tinted here. V4 rebinds RM, so this table itself is kept and
-- its methods are put back before V4.
local SlotSpy={methods=RM,saved={SetTexture=rawget(RM,'SetTexture'),SetVertexColor=rawget(RM,'SetVertexColor')},
 fill=setmetatable({},{__mode='k'}),vertex=setmetatable({},{__mode='k'}),path=setmetatable({},{__mode='k'})}
RM.SetTexture=function(self,...)
 local a,b,c=...
 if type(a)=='number' and type(b)=='number' and type(c)=='number' then SlotSpy.fill[self]={a,b,c};SlotSpy.path[self]=nil
 elseif type(a)=='string' or type(a)=='number' then SlotSpy.fill[self]=nil;SlotSpy.path[self]=a
 elseif a==nil then SlotSpy.fill[self]=nil;SlotSpy.path[self]=nil end
 local prev=SlotSpy.saved.SetTexture
 if prev then return prev(self,...) end
end
RM.SetVertexColor=function(self,...)
 local a,b,c=...
 if type(a)=='number' and type(b)=='number' and type(c)=='number' then SlotSpy.vertex[self]={a,b,c} end
 local prev=SlotSpy.saved.SetVertexColor
 if prev then return prev(self,...) end
end
UIParent:SetSize(1920,1080)
G.UseFont(G.MODELS.default)

local board={observed=true,title='Ember Watch '..string.rep('Long ',30),lines={'Light 4 braziers','Guard the Ember Gate'},rewards={}}
Nexus.CallboardStatus.GetSummary=function() return board end

local function Model(o)
 o=o or {}
 return {status='ready',level=40,auto=o.auto==nil and false or o.auto,paused=o.paused,effective=o.effective,
  cards=o.cards or {{text='Frostwake Sigil (Rare)'}},recommendation=o.recommendation or 'Take Frostwake Sigil.',
  charges=not o.noCharges and (o.charges or {banish=2,reroll=3,freeze=1,arrived=true}) or nil,
  progress={wishlistName='Review plan',total=6,owned=2,missing={'Cinder Lattice x2 (Rare:x2)','Hollow Bell'},
   shed={'Ashen Tithe'},toLock={'Gravecall Chorus'},unknownTomes={'Frostwake Sigil'}}}
end
local function Effects()
 return table.concat({'actions='..#H.actions,'sent='..#H.sent,'granted='..tostring(H.grantedRequests or 0),
  'slots='..tostring(H.slotRequests or 0),'saved='..F.Serialize(NexusDB),
  'auto='..tostring(Nexus.RecomputeStats().autoEnabled==true)},' ')
end

C.setup(Nexus.StartupStatus().coreReady==true,'fixture: local start-up is ready')
Nexus.DisableOrdinaryAutomation()
P.Show()
C.setup(P.Render(Model())==true and NexusPanel:IsShown(),'fixture: the panel renders')
local root=NexusPanel

-- The client's hide reaches every shown descendant (OnHide), and a show
-- brings their OnShow back; the harness fires only the frame's own script.
local function Propagate(f,script,seen)
 for _,c in ipairs(f.children or {}) do
  if c.shown and not seen[c] then
   seen[c]=true
   local fn=c.scripts and c.scripts[script]
   if fn then fn(c) end
   Propagate(c,script,seen)
  end
 end
end
rawset(root,'Hide',function(self) local was=self.shown;RM.Hide(self);if was then Propagate(self,'OnHide',{}) end end)
rawset(root,'Show',function(self) local was=self.shown;RM.Show(self);if not was then Propagate(self,'OnShow',{}) end end)

local Move={starts=0,stops=0,x=400,y=300}
rawset(root,'StartMoving',function() Move.starts=Move.starts+1 end)
rawset(root,'StopMovingOrSizing',function() Move.stops=Move.stops+1 end)
rawset(root,'GetCenter',function() return Move.x,Move.y end)
rawset(UIParent,'GetCenter',function() return 960,540 end)
local function Saved() local s=P.SavedLayoutRoot();return s.panelX,s.panelY end
local function Reset() Move.starts,Move.stops,Move.x,Move.y=0,0,400,300;local s=P.SavedLayoutRoot();s.panelX,s.panelY=nil,nil end
-- Held-Shift fixture scope (the accepted Shift start gate): the original drag
-- scenarios below start their moves with Shift held, as the client's 1. The
-- harness default (false) is unchanged; the query saved here returns before
-- the final cleanup. REG-SLOT changes the held answer only locally.
local RealIsShiftKeyDown=IsShiftKeyDown
local ShiftHeld={value=1}
IsShiftKeyDown=function() return ShiftHeld.value end
local function Start(hit) hit:GetScript('OnDragStart')(hit,'LeftButton') end
local function Stop(hit) hit:GetScript('OnDragStop')(hit) end

C.scenario('V1 a render keeps an active move; a real hide or the origin removal ends it once',function()
 local build=root._contextBuildHit
 Reset();Start(build)
 Move.x=430
 C.setup(P._panelDrag~=nil and Move.starts==1,'V1: fixture: a move from the Build line is active')
 P.Render(Model())
 C.expect(P._panelDrag~=nil and Move.stops==0 and Saved()==nil,
  'V1: a render (its hide reaches the Build line) neither ends the move nor saves',Move.stops..' '..tostring(Saved()))
 board.observed=false
 P.Render(Model())
 board.observed=true
 C.expect(P._panelDrag~=nil and Move.stops==0,'V1: a Callboard row disappearing in a render does not end it')
 P.Render(Model())
 Move.y=320
 root:Hide()
 local x,y=Saved()
 C.expect(P._panelDrag==nil and Move.stops==1 and x==-530 and y==-220,'V1: a real hide of the panel ends it and saves once',
  Move.stops..' '..tostring(x)..','..tostring(y))
 root:Show();P.Render(Model())
 local title=root._callboardTitleHit
 Reset()
 C.setup(title:IsShown(),'V1: fixture: the Callboard title is shown')
 Start(title)
 Move.x=410
 board.observed=false
 P.Render(Model())
 board.observed=true
 C.expect(P._panelDrag==nil and Move.stops==1 and Saved()==-550,'V1: a render that removes the origin ends the move and saves once',
  Move.stops..' '..tostring(Saved()))
 P.Render(Model())
 Reset()
 Start(build);Stop(build)
 C.guard(Move.starts==1 and Move.stops==1,'V1: the next move still works')
end)

local function Rect(r) return G.Rect(r,root) end
local function Width(fs) return G.Length(G.Visible(fs:GetText() or ''))*G.model.char end

C.scenario('V2 Charges, recommendation and Details headings fit their text; the destination row takes no input',function()
 for _,model in ipairs({G.MODELS.default,G.MODELS.px16}) do
  G.UseFont(model)
  P.TogglePlanDetails()
  if not P._playDetails then P.TogglePlanDetails() end
  P.Render(Model({recommendation='Take it.'}))
  local tag=' ('..model.name..')'
  local charges,cHit=root._chargesText,root._chargesHover
  if C.setup(charges:IsShown() and cHit:IsShown() and V.Plain(charges:GetText())~='','V2: fixture: the Charges line is shown'..tag) then
   local t,h=Rect(charges),Rect(cHit)
   local w=math.min(t[3]-t[1],Width(charges)+4)
   C.expect(math.abs(h[3]-t[3])<0.01 and math.abs((h[3]-h[1])-w)<0.01 and h[2]==t[2],
    'V2: the Charges hover ends at its right edge and is as wide as its text plus 4'..tag,G.Text(h)..' in '..G.Text(t))
  end
  local rec,rHit=root._rollRec,root._recommendationHover
  if C.setup(rec:IsShown() and rHit:IsShown(),'V2: fixture: the recommendation is shown'..tag) then
   local t,h=Rect(rec),Rect(rHit)
   C.expect(h[1]==t[1] and h[2]==t[2] and h[3]-h[1]<t[3]-t[1] and h[3]-h[1]>=Width(rec)
    and h[4]-h[2]<=t[4]-t[2] and h[4]-h[2]>=model.line,
    'V2: a one-line recommendation hover covers its line, not the whole box'..tag,G.Text(h)..' in '..G.Text(t))
  end
  -- The Details headings (shown with Show details): each hover is fitted
  -- to its heading's text, never wider than the heading.
  for _,hit in ipairs({root._needLabelHit,root._shedLabelHit}) do
   if C.setup(hit and hit:IsShown(),'V2: fixture: a Details heading hover is shown'..tag) then
    local label=#hit.points==1 and hit.points[1][2] or nil
    local ok=label~=nil and type(label)=='table' and label.kind=='FontString'
    if ok then
     local t,h=Rect(label),Rect(hit)
     ok=h[1]==t[1] and h[3]<=t[3] and h[3]-h[1]>=math.min(t[3]-t[1],Width(label))
    end
    C.expect(ok,'V2: a shown Details heading hover is fitted to its heading'..tag)
   end
  end
 end
 G.UseFont(G.MODELS.default)
 local long=string.rep('Take the needed Echo when it is offered. ',8)
 P.Render(Model({recommendation=long}))
 local t,h=Rect(root._rollRec),Rect(root._recommendationHover)
 C.expect(h[1]==t[1] and h[3]==t[3] and h[4]==t[4],'V2: an overflowing recommendation keeps its whole box',G.Text(h)..' in '..G.Text(t))
 local tip=table.concat(V.TooltipLines(root._recommendationHover:GetScript('OnEnter'),root._recommendationHover),' ')
 C.guard(tip:find('Take the needed Echo when it is offered.',1,true)~=nil,'V2: its hover still shows the complete text')
 P.Render(Model({noCharges=true}))
 C.guard(not root._chargesHover:IsShown(),'V2: without a Charges line its hover is hidden')
 local row=root._destinationRow
 C.guard(row and not row:IsVisible(),'V2: the destination row is not shown in this layout, so its hovers take no input')
 if P._playDetails then P.TogglePlanDetails() end
 P.Render(Model())
end)

-- The shared tooltip with an owner (the harness keeps none).
local function WithTip(fn)
 local tip=GameTooltip
 local set,get=rawget(tip,'SetOwner'),rawget(tip,'GetOwner')
 rawset(tip,'SetOwner',function(self,owner) self._owner=owner end)
 rawset(tip,'GetOwner',function(self) return self._owner end)
 local ok,err=pcall(fn,tip)
 rawset(tip,'SetOwner',set);rawset(tip,'GetOwner',get);tip._owner=nil;tip:Hide()
 assert(ok,err)
end

C.scenario('V3 during a move the Callboard title and objective leave no tooltip of theirs open',function()
 P.Render(Model())
 local title,line,build=root._callboardTitleHit,root._callboardLineHit,root._contextBuildHit
 C.setup(title:IsShown() and LM.Shortened(root._callboardTitle),'V3: fixture: the Callboard title is shown shortened')
 WithTip(function(tip)
  tip:Hide();title:GetScript('OnEnter')(title)
  C.guard(tip:IsShown() and tip._owner==title,'V3: without a move the shortened title shows its complete text')
  title:GetScript('OnLeave')(title)
  tip:Hide();line:GetScript('OnEnter')(line)
  C.guard(tip:IsShown() and tip._owner==line,'V3: without a move the objective shows its complete lines')
  line:GetScript('OnLeave')(line)
  Reset();Start(build)
  tip:Hide();title:GetScript('OnEnter')(title)
  C.expect(not (tip:IsShown() and tip._owner==title),'V3: during a move the title leaves no tooltip open')
  tip:Hide();line:GetScript('OnEnter')(line)
  C.expect(not (tip:IsShown() and tip._owner==line),'V3: during a move the objective leaves no tooltip open')
  -- A title that fits opens no tooltip of its own: another frame's stays.
  local long=board.title
  board.title='Ember Watch'
  P.Render(Model())
  local other=CreateFrame('Frame','FixtureForeignTipOwner',UIParent)
  tip:SetOwner(other);tip:Show()
  title:GetScript('OnEnter')(title)
  C.guard(tip:IsShown() and tip._owner==other,'V3: a tooltip another frame owns stays open while hovering the title during a move')
  board.title=long
  Stop(build)
  P.Render(Model())
 end)
end)

C.scenario('V5 FitToScreen refuses infinite sizes and keeps the scale',function()
 local f=CreateFrame('Frame','FixtureInfiniteWindow',UIParent)
 f:SetSize(420,400);f:SetScale(1)
 UIParent:SetSize(1920,824)
 C.guard(LM.FitToScreen(f,nil,1.5)==1.5,'V5: a finite 420x400 window on 1920x824 fits at the 1.5 ceiling')
 f:SetScale(1)
 for _,case in ipairs({{'an infinite frame and screen width',math.huge,400,math.huge,824},
  {'an infinite frame width',math.huge,400,1920,824},{'an infinite screen height',420,400,1920,math.huge},
  {'an infinite frame height',420,math.huge,1920,824}}) do
  f:SetSize(case[2],case[3]);UIParent:SetSize(case[4],case[5]);f:SetScale(1)
  local got=LM.FitToScreen(f,nil,1.5)
  C.expect(got==nil and f:GetScale()==1,'V5: '..case[1]..' is not acted on and keeps the scale',tostring(got)..' '..tostring(f:GetScale()))
 end
 UIParent:SetSize(1920,1080)
end)

-- The frozen pause API as a boundary double.
local D
local function Double()
 D={paused=false,epoch=0,pauses=0,resumes=0}
 Nexus.SessionPause={
  IsPaused=function() return D.paused end,
  Status=function() return {paused=D.paused,epoch=D.epoch,reason=D.paused and 'session_pause' or nil} end,
  Pause=function() D.pauses=D.pauses+1;if not D.paused then D.paused=true;D.epoch=D.epoch+1 end
   return {paused=D.paused,epoch=D.epoch,reason='session_pause'} end,
  Resume=function() D.resumes=D.resumes+1;if D.paused then D.paused=false;D.epoch=D.epoch+1 end
   return {paused=D.paused,epoch=D.epoch} end,
 }
end
local CB={refresh=0,toggle=0}
P.Init({RefreshDisplay=function() CB.refresh=CB.refresh+1;return true end,
 ToggleAuto=function() CB.toggle=CB.toggle+1;return false end})
local function Row(prefix)
 for _,item in ipairs(P.MoreMenuItems(root._menuBtn)) do
  if type(item.text)=='string' and V.Plain(item.text):sub(1,#prefix)==prefix then return item end
 end
end
local function Hover()
 local b=root._autoBtn
 local lines=V.TooltipLines(b:GetScript('OnEnter'),b)
 for i,l in ipairs(lines) do lines[i]=V.Plain(l) end
 return table.concat(lines,'\n')
end
local function Details()
 local row=Row('Auto explained')
 row.func(row)
 local body=V.Plain(NexusHelpWindow.body:GetText())
 Nexus.Help.Hide()
 return body
end

C.scenario('V6 after a confirmed pause an unreadable Status is shown as unknown',function()
 Double()
 P.Render(Model())
 local pause=Row('Pause Nexus for this session')
 pause.func(pause)
 C.setup(D.paused and V.Plain(root._contextTitle:GetText()):find('Nexus paused',1,true)==1,'V6: fixture: Nexus is confirmed paused')
 local before=Effects()
 for _,case in ipairs({{'fails',function() error('status read failed') end},{'is malformed',function() return {paused='?'} end}}) do
  Nexus.SessionPause.Status=case[2]
  P.Render(Model())
  local row=Row('Pause Nexus') or Row('Resume Nexus') or Row('Session pause')
  local text=row and (V.Plain(row.text)..' '..tostring(row.tooltipText)) or ''
  C.expect(row and row.disabled==true and row.func==nil,'V6: when Status '..case[1]..' the control is disabled',text)
  C.expect(text~='' and not text:find('nothing is paused',1,true) and not text:find('not paused',1,true)
   and (text:find('cannot be read',1,true) or text:find('unknown',1,true)),
   'V6: when Status '..case[1]..' it says the pause state cannot be read, not that nothing is paused',text)
  C.expect(not V.Plain(root._contextTitle:GetText()):find('paused',1,true),'V6: the title claims neither paused nor unpaused')
  C.expect(Hover():find('cannot be read',1,true)~=nil,'V6: the Auto hover says the session pause cannot be read',Hover())
 end
 C.guard(Effects()==before and D.resumes==0,'V6: reading an unknown status changes nothing and resumes nothing',Effects())
 Nexus.SessionPause=nil
 P.Render(Model())
end)

C.scenario('V7 a confirmed pause overrides the committed Auto state words; Resume restores them',function()
 Double()
 P.Render(Model({auto=true,effective={state='ready'}}))
 C.setup(Hover():find('Now: ready',1,true)~=nil,'V7: fixture: the committed model says Now: ready')
 local before=Effects()
 local cb={CB.refresh,CB.toggle}
 local pause=Row('Pause Nexus for this session')
 pause.func(pause)
 local hover=Hover()
 C.expect(hover:find('Now: ready',1,true)==nil and hover:find('Now: paused for this session',1,true)~=nil,
  'V7: the hover says the session pause holds Auto, not Now: ready',hover)
 local body=Details()
 C.expect(body:find('Now: ready',1,true)==nil and body:find('Paused because: Nexus is paused for this session',1,true)~=nil
  and body:find('(autoPick): ',1,true)~=nil,'V7: the details give the session pause as the hold and keep every permission',body:sub(-500))
 local resume=Row('Resume Nexus')
 resume.func(resume)
 C.expect(Hover():find('Now: ready',1,true)~=nil,'V7: after Resume the model\'s own state words return')
 C.guard(CB.refresh==cb[1] and CB.toggle==cb[2],'V7: neither Pause nor Resume ran a refresh step or an Auto toggle')
 C.guard(Effects()==before,'V7: no action, send, ownership or slot request, saved change or Auto change',Effects())
 Nexus.SessionPause=nil
 P.Render(Model())
end)

-- Re-review of 6f9d04f, item 1: the origin can disappear with a hidden
-- ancestor while its own shown flag stays set.
C.scenario('V8 a render that hides the drag origin\'s parent ends the move once; a visible origin keeps it',function()
 P.Render(Model())
 local hover=root._recommendationHover
 C.setup(hover:IsVisible() and root._rollArea:IsShown(),'V8: fixture: the recommendation hover is visible in the roll area')
 Reset();Start(hover)
 P.Render(Model())
 C.guard(P._panelDrag~=nil and Move.stops==0 and Saved()==nil,'V8: a render that keeps the roll area keeps the move and saves nothing')
 Move.x=440
 P.Render(Model({cards={},recommendation=''}))
 C.setup(not root._rollArea:IsShown() and hover:IsShown() and not hover:IsVisible(),
  'V8: fixture: the no-offer render hides the roll area; the hover is shown but not visible')
 C.expect(P._panelDrag==nil and Move.stops==1 and Saved()==-520,
  'V8: the move from the now-invisible hover ends once and saves its movement',Move.stops..' '..tostring(Saved()))
 P.Render(Model({cards={},recommendation=''}))
 C.guard(Move.stops==1,'V8: a later render stops nothing again')
 P.Render(Model())
 Reset();Start(hover)
 P.Render(Model({cards={},recommendation=''}))
 C.expect(P._panelDrag==nil and Move.stops==1 and Saved()==nil,'V8: an origin that disappears without movement ends the move and saves nothing',
  Move.stops..' '..tostring(Saved()))
 P.Render(Model())
end)

-- Re-review of 6f9d04f, item 2: after a confirmed pause, an unreadable
-- Status leaves the current state unknown, never the cached ready.
C.scenario('V9 ready, then Pause, then an unreadable Status: the hover and details stay unknown',function()
 Double()
 P.Render(Model({auto=true,effective={state='ready'}}))
 C.setup(Hover():find('Now: ready',1,true)~=nil,'V9: fixture: the committed model says Now: ready')
 local pause=Row('Pause Nexus for this session')
 pause.func(pause)
 C.setup(D.paused and Hover():find('Now: paused for this session',1,true)~=nil,'V9: fixture: Nexus is confirmed paused')
 local before=Effects()
 local cb={CB.refresh,CB.toggle}
 local status=Nexus.SessionPause.Status
 for _,case in ipairs({{'fails',function() error('status read failed') end},{'is malformed',function() return {paused='?'} end}}) do
  Nexus.SessionPause.Status=case[2]
  local hover=Hover()
  C.expect(hover:find('cannot be read',1,true)~=nil and hover:find('Now: ready',1,true)==nil
   and hover:find('Now: paused for this session',1,true)==nil,
   'V9: when Status '..case[1]..' the hover says unknown, neither ready nor paused',hover)
  local body=Details()
  C.expect(body:find('cannot be read',1,true)~=nil and body:find('Now: ready',1,true)==nil
   and body:find('Now: paused for this session',1,true)==nil and body:find('(autoPick): ',1,true)~=nil
   and body:find('Orb runs: never by Auto',1,true)~=nil,
   'V9: when Status '..case[1]..' the details say unknown and keep every permission',body:sub(-400))
 end
 Nexus.SessionPause.Status=status
 C.guard(Hover():find('Now: paused for this session',1,true)~=nil,'V9: a readable confirmed pause is said again')
 local resume=Row('Resume Nexus')
 resume.func(resume)
 C.guard(Hover():find('Now: ready',1,true)~=nil and Details():find('Now: ready',1,true)~=nil,
  'V9: a readable unpaused status gives back the model\'s own state words')
 C.guard(CB.refresh==cb[1] and CB.toggle==cb[2] and D.resumes==1,'V9: no refresh step or Auto toggle; one Resume, by the click')
 C.guard(Effects()==before,'V9: no action, send, ownership or slot request, saved change or Auto change',Effects())
 Nexus.SessionPause=nil
 P.Render(Model())
end)

-- REG-SLOT (S3_OFFER_EMPTY_SLOT / MI-F01): an offer whose Echo has no
-- verified icon shows an EMPTY slot before its name, inside its own compact
-- row, tinted with the Echo rarity colour of the card's own quality
-- (OrbHistory.QUALITY_COLORS); an unknown own quality, a name ending in
-- "(Rare)" included, stays neutral (white, as the name). No icon path or id
-- (these model cards carry no spell id; REG-ICON below covers those that do).
-- The slot is what the card's real region tree shows apart from its fill,
-- edges and three texts; its tint is what SetTexture / SetVertexColor
-- received (SlotSpy). EXPECT: the slot, its tint and its geometry (absent at
-- a171db9c). GUARD: current text, tag, hover, edges, band, hidden cards,
-- passive input and the Shift drag. Model geometry only: native pixel fit
-- and desktop 125% are NOT RUN.
local S={QC=Nexus.OrbHistory and Nexus.OrbHistory.QUALITY_COLORS or {}}
function S.Offer(name,q,note)
 local qn=q and Nexus.OrbHistory.QUALITY_NAMES[q]
 return {text=name..(qn and (' ('..qn..')') or '')..(note and (' '..note) or ''),facts=Nexus.Readout.CardFacts({name=name,quality=q})}
end
function S.Same(c,q)
 return type(c)=='table' and type(q)=='table' and math.abs(c[1]-q[1])<0.001 and math.abs(c[2]-q[2])<0.001 and math.abs(c[3]-q[3])<0.001
end
function S.Rect(r) local ok,v=pcall(G.Rect,r,root);return ok and v or nil end
-- The card's own descendants apart from its fill, four edges and three texts,
-- each once: the harness lists a created Texture or FontString both as a
-- region and as a child (as G.Shown notes), so both routes use the same skip
-- and seen sets. Unknown descendants are kept; frames are walked into.
function S.Parts(card)
 local skip,seen,out={},{},{}
 for _,k in ipairs({'fill','name','quality','tag'}) do if card[k] then skip[card[k]]=true end end
 for _,e in ipairs(type(card.edges)=='table' and card.edges or {}) do skip[e]=true end
 local function Walk(f)
  for _,list in ipairs({{f:GetRegions()},{f:GetChildren()}}) do
   for _,c in ipairs(list) do
    if not skip[c] and not seen[c] then
     seen[c]=true
     out[#out+1]=c
     local kind=c.GetObjectType and c:GetObjectType()
     if kind~='Texture' and kind~='FontString' then Walk(c) end
    end
   end
  end
 end
 Walk(card)
 return out
end
function S.AnyVisible(f)
 for _,r in ipairs({f:GetRegions()}) do if r:IsVisible() then return true end end
 for _,c in ipairs({f:GetChildren()}) do if c:IsVisible() or S.AnyVisible(c) then return true end end
 return false
end
-- The slot is the union of the card's own painted visuals only: shown
-- Textures among S.Parts that received a colour, a vertex colour or a
-- texture (SlotSpy) and have a positive rectangle. A container frame is
-- walked, never counted by its own box; a text is never the slot. Each
-- visual keeps its identity and its recorded colours.
function S.Slot(card)
 local box,tints,paths,visuals=nil,{},{},{}
 for _,p in ipairs(S.Parts(card)) do
  local kind=p.GetObjectType and p:GetObjectType()
  local fill,vertex,path=SlotSpy.fill[p],SlotSpy.vertex[p],SlotSpy.path[p]
  local painted=fill~=nil or vertex~=nil or path~=nil
  local r=kind=='Texture' and painted and p:IsVisible() and S.Rect(p) or nil
  if r and r[3]-r[1]>0 and r[4]-r[2]>0 then
   box=box and {math.min(box[1],r[1]),math.min(box[2],r[2]),math.max(box[3],r[3]),math.max(box[4],r[4])} or {r[1],r[2],r[3],r[4]}
   if fill then tints[#tints+1]=fill end
   if vertex then tints[#tints+1]=vertex end
   if path~=nil then paths[#paths+1]=path end
   visuals[#visuals+1]={region=p,fill=fill,vertex=vertex,path=path}
  end
 end
 return box,tints,paths,visuals
end
function S.Observe(i)
 local card=root._offerCards and root._offerCards[i]
 if not card then return nil end
 local o={card=card,visible=card:IsVisible(),rect=S.Rect(card),texts={}}
 for _,k in ipairs({'name','quality','tag'}) do
  local t=card[k]
  o.texts[k]={text=t and t:GetText() or '',rect=t and S.Rect(t) or nil}
 end
 o.slot,o.tints,o.paths,o.visuals=S.Slot(card)
 return o
end
function S.Placed(o)
 if not (o and o.visible and o.rect) then return false,'card not visible' end
 local s=o.slot
 if not s then return false,'no visible slot apart from the fill, edges and texts' end
 if not G.Inside(s,o.rect,0.01) then return false,'slot '..G.Text(s)..' outside its row '..G.Text(o.rect) end
 local name=o.texts.name.rect
 if not (name and s[3]<=name[1]+0.01) then return false,'slot '..G.Text(s)..' leaves no space before the name' end
 for _,k in ipairs({'name','quality','tag'}) do
  local t=o.texts[k]
  if t.text~='' and t.rect and not G.Apart(s,t.rect) then return false,'slot '..G.Text(s)..' overlaps the '..k end
 end
 for _,p in ipairs(o.paths) do
  if type(p)=='number' or (type(p)=='string' and p:lower():find('icons',1,true)) then return false,'an icon texture '..tostring(p) end
 end
 return true,G.Text(s)
end
function S.Tint(o,q) for _,c in ipairs(o and o.tints or {}) do if S.Same(c,S.QC[q]) then return true end end return false end
function S.Rarity(o) for q=1,4 do if S.Tint(o,q) then return q end end return nil end
function S.Only(o,q)
 if not S.Tint(o,q) then return false end
 for r=1,4 do if r~=q and S.Tint(o,r) then return false end end
 return true
end
function S.Tints(o)
 local out={}
 for _,c in ipairs(o and o.tints or {}) do out[#out+1]=string.format('%.2f/%.2f/%.2f',c[1],c[2],c[3]) end
 return 'tints '..table.concat(out,' ')
end
-- The effective numeric tint of one slot visual: its colour texture times its
-- vertex colour (each 1,1,1 when not recorded); nil when neither was recorded.
function S.Effective(v)
 if not (v and (v.fill or v.vertex)) then return nil end
 local f,x=v.fill or {1,1,1},v.vertex or {1,1,1}
 return {f[1]*x[1],f[2]*x[2],f[3]*x[3]}
end
-- The slot visuals (identities) whose effective tint is exactly `rgb`.
function S.Bearing(o,rgb)
 local out={}
 for _,v in ipairs(o and o.visuals or {}) do if S.Same(S.Effective(v),rgb) then out[#out+1]=v.region end end
 return out
end
-- Whether one of `regions` is in `set`: the same reused visual as before.
function S.Tracked(regions,set)
 for _,r in ipairs(regions) do if set[r] then return true end end
 return false
end
S.WHITE={1,1,1}
-- Known own quality: the slot, only its rarity colour, and a visual that shows
-- it; unknown: the slot, no rarity colour, and a visual that is white 1,1,1.
function S.Fallback(o,q)
 local placed,why=S.Placed(o)
 if not placed then return false,why end
 if q then return S.Only(o,q) and #S.Bearing(o,S.QC[q])>0,why..' '..S.Tints(o) end
 return S.Rarity(o)==nil and #S.Bearing(o,S.WHITE)>0,why..' '..S.Tints(o)
end
function S.Meaning(model,i,o)
 local R=Nexus.Readout
 local cards=model.cards
 local marked=R.MarkedCard and R.MarkedCard(cards) or nil
 local frozen=model.auto==false and not marked and R.FreezeCard and R.FreezeCard(cards) or nil
 local c=cards[i]
 local shown=R.OfferCard(c.text,marked==i,model.auto,type(c.facts)=='table' and c.facts or nil,frozen==i)
 local want=tostring(shown.name)..' | '..tostring(shown.quality)..' | '..tostring(shown.shown or shown.tag)
 if not o then return false,shown,'no card vs '..want end
 local got=o.texts.name.text..' | '..o.texts.quality.text..' | '..o.texts.tag.text
 return got==want,shown,got..' vs '..want
end
function S.Band(o)
 local roll=S.Rect(root._rollArea)
 if not (o and o.rect and roll and G.Inside(o.rect,roll,0.01)) then return false,'row outside the roll box' end
 if math.abs((o.card:GetHeight() or 0)-(o.card.name:GetHeight() or 0))>0.01 then return false,'row height is not its text height' end
 local placed={}
 for _,k in ipairs({'name','quality','tag'}) do
  local t=o.texts[k]
  if t.text~='' then
   if not (t.rect and G.Inside(t.rect,o.rect,0.01)) then return false,k..' outside its row' end
   for _,u in ipairs(placed) do if not G.Apart(t.rect,u[2]) then return false,k..' overlaps '..u[1] end end
   placed[#placed+1]={k,t.rect}
  end
 end
 return true,G.Text(o.rect)
end
function S.Edges(o)
 local e=o and o.card.edges
 if type(e)~='table' or #e~=4 then return false end
 for i=1,4 do
  local c=SlotSpy.fill[e[i]]
  if not (S.Same(c,{0.32,0.32,0.38}) or S.Same(c,{1,0.82,0})) then return false end
 end
 return true
end
function S.TextureIds()
 local cards,ids={},{}
 for _,c in ipairs(root._offerCards or {}) do cards[c]=true end
 for _,f in ipairs(H.frames) do
  local owned,p=false,f
  while p do if cards[p] then owned=true;break end p=p.parent end
  if not owned then
   for _,r in ipairs({f:GetRegions()}) do
    local t=r:GetTexture()
    if type(t)=='string' then ids[r]=t end
   end
  end
 end
 return ids
end
-- REG-SLOT baseline settle. F.Boot returns as soon as community start-up is
-- ready; the ordinary start-up work after it (deferred Store maintenance:
-- compaction and retention, their catalog notification and the delayed view
-- refresh, and the Auto-OFF poll) runs only on later host ticks. With Auto
-- OFF, no move and no card action, real H.Advance(.05,.05) ticks (40 at most,
-- the .2 s idle proof included) run until every read-only observation in
-- S.Settled holds; then a whole .2 s window (four ticks) must leave Effects()
-- and both CB counters exactly as they were while those observations still
-- hold. Nothing is reset, cancelled, disabled or deleted; a settle that does
-- not happen stays a SETUP failure.
S.settle={ok=false,ticks=0,why='not observed'}
function S.Settled()
 if P._panelDrag~=nil then return false,'a move is active' end
 if Nexus.RecomputeStats().autoEnabled==true then return false,'Auto is ON' end
 local st=type(Nexus.StartupStatus)=='function' and Nexus.StartupStatus() or nil
 if not (type(st)=='table' and st.coreReady==true and st.state=='ready') then
  return false,'start-up '..tostring(st and st.state)..' coreReady='..tostring(st and st.coreReady)
 end
 local DC,DR,BC,VR,SC=Nexus.DataCompaction,Nexus.DataRetention,Nexus.BuildCatalog,Nexus.ViewRefresh,Nexus.Scheduler
 if not (type(DC)=='table' and type(DC.Stats)=='function') then return false,'no DataCompaction.Stats' end
 local cs=DC.Stats(NexusDB)
 if not (type(cs)=='table' and cs.pending==false and cs.phase=='done') then
  return false,'compaction phase='..tostring(cs and cs.phase)..' pending='..tostring(cs and cs.pending)
 end
 if not (type(DR)=='table' and type(DR.Stats)=='function') then return false,'no DataRetention.Stats' end
 local rs=DR.Stats(NexusDB)
 if not (type(rs)=='table' and rs.pending==false) then return false,'retention pending='..tostring(rs and rs.pending) end
 if not (type(BC)=='table' and type(BC.RootState)=='function') then return false,'no BuildCatalog.RootState' end
 local cr=BC.RootState()
 if not (type(cr)=='table' and cr.state=='ROOT_ADMITTED' and cr.candidate==false) then
  return false,'catalog '..tostring(cr and cr.state)..' candidate='..tostring(cr and cr.candidate)
 end
 if not (type(VR)=='table' and type(VR.Key)=='function' and type(SC)=='table' and type(SC.Pending)=='function') then
  return false,'no ViewRefresh.Key / Scheduler.Pending'
 end
 local key=VR.Key()
 if key==nil then return false,'no view refresh key' end
 if SC.Pending(key)~=nil then return false,'view refresh pending' end
 return true,'settled'
end
do
 local okSettle,errSettle=pcall(function()
  local budget=40
  local function Tick()
   local ok,err=pcall(H.Advance,.05,.05)
   S.settle.ticks=S.settle.ticks+1
   if not ok then S.settle.why='a tick raised: '..tostring(err) end
   return ok
  end
  local function Observe()
   local ok,ready,why=pcall(S.Settled)
   if not ok then return false,'an observation raised: '..tostring(ready),true end
   return ready,why,false
  end
  local stop=false
  while not stop and not S.settle.ok and S.settle.ticks<budget do
   local ready,why,broken=Observe()
   S.settle.why=why
   if broken then stop=true
   elseif not ready then stop=not Tick()
   elseif S.settle.ticks+4>budget then
    S.settle.why='settled after '..S.settle.ticks..' ticks; no room left for the .2 s idle window';stop=true
   else
    P.Render(Model())
    local e0,r0,t0=Effects(),CB.refresh,CB.toggle
    local quiet=true
    for _=1,4 do
     if not Tick() then quiet,stop=false,true;break end
     local still,w,bad=Observe()
     if bad or not still then quiet,S.settle.why=false,'idle window: '..tostring(w);stop=bad;break end
     if Effects()~=e0 or CB.refresh~=r0 or CB.toggle~=t0 then
      quiet=false
      S.settle.why='idle window: effects or callbacks changed (refresh '..r0..'->'..CB.refresh..', toggle '..t0..'->'..CB.toggle..')'
      break
     end
    end
    if quiet then S.settle.ok,S.settle.why=true,'settled; a .2 s idle window changed nothing' end
   end
  end
 end)
 if not okSettle then S.settle.ok,S.settle.why=false,'the settle raised: '..tostring(errSettle) end
end
C.setup(S.settle.ok,'REG-SLOT: fixture: ordinary start-up work has settled and a .2 s idle window changes nothing before the baseline',
 S.settle.why..' after '..S.settle.ticks..' of 40 ticks')
S.keep={effects=Effects(),cb={CB.refresh,CB.toggle},font=G.model,move={Move.starts,Move.stops,Move.x,Move.y},
 drag=P._panelDrag,textures=S.TextureIds()}
do local s=P.SavedLayoutRoot();S.keep.scale,S.keep.x,S.keep.y=rawget(s,'panelScale'),rawget(s,'panelX'),rawget(s,'panelY') end
-- Test-local state back as it was: no active move (ended by the root's real
-- mouse-up), Shift held, the chosen size and position, Move, the font model,
-- and the ordinary model.
function S.Restore()
 local up=root:GetScript('OnMouseUp')
 if P._panelDrag and up then ShiftHeld.value=1;pcall(up,root,'LeftButton') end
 ShiftHeld.value=1
 local s=P.SavedLayoutRoot()
 s.panelScale,s.panelX,s.panelY=S.keep.scale,S.keep.x,S.keep.y
 P.ApplyPanelScale()
 Move.starts,Move.stops,Move.x,Move.y=S.keep.move[1],S.keep.move[2],S.keep.move[3],S.keep.move[4]
 G.UseFont(S.keep.font)
 P.Render(Model())
end

C.scenario('REG-SLOT-0 controls: start-up, Auto OFF, real cards keep their current text, hover, band and edges',function()
 C.setup(Nexus.StartupStatus().coreReady==true,'REG-SLOT: fixture: local start-up is ready')
 C.setup(S.keep.drag==nil and P._panelDrag==nil,'REG-SLOT: fixture: no move is active from an earlier scenario')
 C.guard(S.keep.effects:find('auto=false',1,true)~=nil,'REG-SLOT: Auto is OFF before the offer checks',S.keep.effects:match('auto=%S+'))
 local m=Model({cards={S.Offer('Frostwake Sigil',2),S.Offer('Hollow Bell',3,'Owned 1 of 2'),S.Offer('Ashen Crown (Rare)',nil)}})
 P.Render(m)
 for i=1,3 do
  local o=S.Observe(i)
  if C.setup(o~=nil and o.visible,'REG-SLOT: fixture: offer card '..i..' is shown') then
   local ok,shown,detail=S.Meaning(m,i,o)
   C.guard(ok,'REG-SLOT: card '..i..' keeps the Readout name, quality and tag',detail)
   local band,why=S.Band(o)
   C.guard(band,'REG-SLOT: card '..i..' keeps its compact row in the roll box, its texts inside and apart',why)
   C.guard(S.Edges(o),'REG-SLOT: card '..i..' keeps its fixed status edges')
   local tip=V.Plain(table.concat(V.TooltipLines(o.card:GetScript('OnEnter'),o.card),' '))
   C.guard(tip:find(V.Plain(shown.full),1,true)~=nil,'REG-SLOT: card '..i..'\'s hover shows its complete line',tip)
  end
 end
end)

C.scenario('REG-SLOT-1 one reused card: its own rarity tints its empty slot; an unknown quality stays neutral',function()
 local first=root._offerCards and root._offerCards[1]
 local states={
  {'own rarity 2',S.Offer('Frostwake Sigil',2),2},
  {'own rarity 3',S.Offer('Frostwake Sigil',3),3},
  {'an unknown own quality and a name ending (Rare)',S.Offer('Frostwake Sigil (Rare)',nil),nil},
  {'no own facts (a quality only in its text)',{text='Frostwake Sigil (Rare)'},nil},
  {'own rarity 2 again',S.Offer('Frostwake Sigil',2),2},
 }
 local placed,counts,bearers={},{},{}
 for n,st in ipairs(states) do
  local m=Model({cards={st[2]}})
  P.Render(m)
  local o=S.Observe(1)
  if C.setup(o~=nil and o.visible and o.card==first,'REG-SLOT: fixture: the same first card is shown with '..st[1]) then
   local ok,_,detail=S.Meaning(m,1,o)
   C.guard(ok,'REG-SLOT: with '..st[1]..' the card keeps its Readout name, quality and tag',detail)
   local at,why=S.Placed(o)
   placed[n],counts[n]=at,#S.Parts(first)
   C.expect(at,'REG-SLOT: with '..st[1]..' the card shows an empty slot inside its row, before the name, apart from its texts',why)
   if st[3] then
    local bearing=S.Bearing(o,S.QC[st[3]])
    C.expect(at and S.Only(o,st[3]) and #bearing>0 and (next(bearers)==nil or S.Tracked(bearing,bearers)),
     'REG-SLOT: with '..st[1]..' the slot carries Echo rarity colour '..st[3]..' and no other, on the same reused visual',S.Tints(o))
    for _,r in ipairs(bearing) do bearers[r]=true end
   else
    C.expect(at and S.Rarity(o)==nil and S.Tracked(S.Bearing(o,S.WHITE),bearers),
     'REG-SLOT: with '..st[1]..' the slot stays neutral: its reused tint-bearing visual is white 1,1,1, no rarity colour from the text or the earlier card',S.Tints(o))
   end
  end
 end
 C.expect(placed[1] and placed[#states] and counts[1]==counts[#states],
  'REG-SLOT: the reused card keeps the same slot regions across renders (none added per render)',tostring(counts[1])..' -> '..tostring(counts[#states]))
end)

C.scenario('REG-SLOT-2 fewer, replaced, no and returning offers: hidden cards show nothing; shown ones follow current facts',function()
 local boards={
  {'three offers',{S.Offer('Frostwake Sigil',2),S.Offer('Hollow Bell',3),S.Offer('Ashen Crown (Rare)',nil)},{2,3,nil}},
  {'one offer',{S.Offer('Hollow Bell',3)},{3}},
  {'a replaced board',{S.Offer('Cinder Lattice',1),S.Offer('Gravecall Chorus',2)},{1,2}},
  {'no offer',{},{}},
  {'offers again',{S.Offer('Ember Crown',4),S.Offer('Ashen Tithe (Rare)',nil),S.Offer('Frostwake Sigil',2)},{4,nil,2}},
 }
 for _,b in ipairs(boards) do
  local m=Model({cards=b[2],recommendation=#b[2]==0 and '' or nil})
  P.Render(m)
  for i=1,3 do
   local card=root._offerCards and root._offerCards[i]
   if b[2][i] then
    local o=S.Observe(i)
    if C.setup(o~=nil and o.visible,'REG-SLOT: fixture: with '..b[1]..' card '..i..' is shown') then
     local ok,_,detail=S.Meaning(m,i,o)
     C.guard(ok,'REG-SLOT: with '..b[1]..' card '..i..' shows its current name, quality and tag',detail)
     local fine,why=S.Fallback(o,b[3][i])
     C.expect(fine,'REG-SLOT: with '..b[1]..' card '..i..' shows its empty slot in its current facts\' colour ('..tostring(b[3][i] or 'neutral')..')',why)
    end
   elseif card then
    C.guard(not card:IsVisible() and not S.AnyVisible(card),'REG-SLOT: with '..b[1]..' card '..i..' and everything in it is hidden')
   end
  end
 end
end)

C.scenario('REG-SLOT-3 at 50, 100, 125 and 150% long names and tags keep slot, name, quality and tag inside their row and apart',function()
 for _,scale in ipairs({0.5,1,1.25,1.5}) do
  local pct=string.format('%d%%',math.floor(scale*100+0.5))
  P.SetPanelScale(scale)
  local function Controls()
   return tostring(root._rollRec and root._rollRec:IsShown())..'/'..tostring(root._autoBtn and root._autoBtn:IsShown())
    ..'/'..tostring(root._menuBtn and root._menuBtn:IsShown())
  end
  P.Render(Model({cards={S.Offer('Frostwake Sigil',2),S.Offer('Hollow Bell',3,'Owned 1 of 2'),S.Offer('Ashen Crown',nil)}}))
  local h0,r0,c0=root:GetHeight(),S.Rect(root._rollArea),Controls()
  P.Render(Model({cards={S.Offer(string.rep('Cinderbound ',8)..'Lattice',2,'Owned 2 of 3'),
   S.Offer('Hollow Bell of the '..string.rep('Ashen ',8)..'Choir',4,'Owned 0 of 1'),
   S.Offer(string.rep('Gravecall ',6)..'Chorus (Rare)',nil,'Owned 1 of 1')}}))
  local h1,r1,c1=root:GetHeight(),S.Rect(root._rollArea),Controls()
  C.guard(h1==h0 and r0~=nil and r1~=nil and math.abs((r1[4]-r1[2])-(r0[4]-r0[2]))<0.01 and c1==c0,
   'REG-SLOT: at '..pct..' long names and tags keep the panel height, the roll box and the recommendation and controls',
   tostring(h0)..'->'..tostring(h1)..' '..c0..'->'..c1)
  local want={2,4,nil}
  for i=1,3 do
   local o=S.Observe(i)
   if C.setup(o~=nil and o.visible,'REG-SLOT: fixture: at '..pct..' long card '..i..' is shown') then
    local band,why=S.Band(o)
    C.guard(band,'REG-SLOT: at '..pct..' long card '..i..' keeps its compact row with its texts inside and apart',why)
    local fine,fwhy=S.Fallback(o,want[i])
    C.expect(fine,'REG-SLOT: at '..pct..' long card '..i..' shows its empty slot inside its row, before the name and apart from its texts, in its own colour',fwhy)
   end
  end
 end
 S.Restore()
end)

C.scenario('REG-SLOT-4 the visible card stays passive: a click does nothing; the shared Shift drag starts, holds and ends once',function()
 local m=Model({cards={S.Offer('Frostwake Sigil',2)}})
 P.Render(m)
 local card=root._offerCards and root._offerCards[1]
 if not C.setup(card~=nil and card:IsVisible() and P._panelDrag==nil,'REG-SLOT: fixture: a visible offer card and no active move') then return end
 local up=root:GetScript('OnMouseUp')
 local function Call(hit,script,...)
  local fn=hit and hit:GetScript(script)
  if not fn then return false end
  return (pcall(fn,hit,...))
 end
 local function Tick() return (pcall(H.Advance,.05,.05)) end
 -- Cleanup only, never counted: a move left active ends by its real drag-stop, then the root mouse-up.
 local function Leftover()
  if P._panelDrag then ShiftHeld.value=1;Call(card,'OnDragStop') end
  if P._panelDrag and up then pcall(up,root,'LeftButton') end
 end
 Reset()
 local before=Effects()
 C.guard(card:GetScript('OnClick')==nil and card:GetScript('OnMouseUp')==nil and card._nexusPassiveDrag==true,
  'REG-SLOT: the card chooses nothing: no click or mouse-up of its own; it is a passive drag surface')
 local okClick=pcall(function() card:Click('LeftButton');if up then up(root,'LeftButton') end end)
 C.guard(okClick and Move.starts==0 and Move.stops==0 and P._panelDrag==nil and Effects()==before,
  'REG-SLOT: an ordinary click on the card moves, saves and sends nothing',Effects())
 ShiftHeld.value=1
 local ok1=Call(card,'OnDragStart','LeftButton')
 local owner=P._panelDrag
 C.guard(ok1 and owner~=nil and owner.origin==card and Move.starts==1,'REG-SLOT: with Shift held as 1 a left drag from the card starts one move',Move.starts)
 local okC=Call(root._contextBuildHit,'OnDragStart','LeftButton')
 local okR=Call(card,'OnDragStart','RightButton')
 C.guard(okC and okR and Move.starts==1 and P._panelDrag==owner,
  'REG-SLOT: with Shift held a second left start and a right start are refused and keep the card as origin',Move.starts)
 Move.x=430
 local okT=Tick() and Tick()
 C.guard(okT and P._panelDrag==owner and Move.stops==0 and Saved()==nil,'REG-SLOT: while Shift stays held host ticks keep the move and save nothing')
 ShiftHeld.value=nil
 local okL=Tick()
 local x,y=Saved()
 C.guard(okL and P._panelDrag==nil and Move.stops==1 and type(x)=='number' and x==x and math.abs(x)<math.huge and type(y)=='number' and y==y,
  'REG-SLOT: Shift released, the next host tick ends the move once and saves a finite moved offset',tostring(x)..','..tostring(y))
 local okS=Call(card,'OnDragStop')
 local okU=up~=nil and (pcall(up,root,'LeftButton'))
 local okH=pcall(function() card:Hide();card:Show() end)
 local okT2=Tick()
 local x2,y2=Saved()
 C.guard(okS and okU and okH and okT2 and P._panelDrag==nil and Move.starts==1 and Move.stops==1 and x2==x and y2==y,
  'REG-SLOT: after that end its drag-stop, the root mouse-up, a hide and a tick stop, save or move nothing more',Move.starts..'/'..Move.stops)
 Leftover();P.Render(m)
 Reset();ShiftHeld.value=true
 local okA=Call(card,'OnDragStart','LeftButton')
 local active=P._panelDrag~=nil and P._panelDrag.origin==card and Move.starts==1
 local okB=Call(card,'OnDragStop')
 C.guard(okA and okB and active and P._panelDrag==nil and Move.stops==1,'REG-SLOT: with Shift held as true a left drag from the card starts and its release ends one move')
 Leftover()
 Reset();ShiftHeld.value=nil
 local okN=Call(card,'OnDragStart','LeftButton')
 C.guard(okN and P._panelDrag==nil and Move.starts==0,'REG-SLOT: without Shift a left drag from the card starts nothing')
 Leftover()
 ShiftHeld.value=1
 Reset()
 C.guard(Effects()==before,'REG-SLOT: the card checks change no action, send, ownership or slot request, saved data or Auto',Effects())
 S.Restore()
end)

-- REG-ICON (MI-F01, the verified half): an offer whose model card carries its
-- exact spell id shows the client's own texture for that id in the same slot
-- (GetSpellInfo's third return, as GameAdapter.TomeStateObservation reads it;
-- mocked here with invented paths). The id is the board card's, carried by
-- Readout.CardFacts for named and nameless offers alike; the icon is never
-- taken from a name, a text or another row. Without an id, with an id that is
-- not a positive whole number, or with a lookup that fails, raises or answers
-- anything but a texture, the empty rarity slot of REG-SLOT stays. A reused,
-- replaced or hidden card keeps no earlier texture. One lookup per shown
-- offer per layout pass; none on a settled render; no failure is remembered.
-- EXPECT: the id in the facts and the icon (absent at 4ab0b525). GUARD: names,
-- the generated flag, text, hover, band, edges, the empty slot and passive
-- input. Model geometry only: the native icon render is NOT RUN.
S.icon={real=GetSpellInfo,calls={},map={}}
function S.icon.Lookup(id,...)
 S.icon.calls[#S.icon.calls+1]=id
 local v=S.icon.map[id]
 if type(v)=='function' then return v(id) end
 if v~=nil then return 'Fixture spell '..tostring(id),nil,v end
 return S.icon.real(id,...)
end
function S.icon.Use(map) S.icon.calls,S.icon.map={},map or {};GetSpellInfo=S.icon.Lookup end
function S.icon.Restore() GetSpellInfo=S.icon.real;S.icon.calls,S.icon.map={},{} end
function S.icon.Path(id) return 'Interface\\Icons\\Fixture_Echo_'..tostring(id) end
function S.icon.Asked(id) local n=0;for _,v in ipairs(S.icon.calls) do if v==id then n=n+1 end end return n end
-- A model card as the runtime builds it: the CardLine text and the CardFacts of
-- one board card (name, own quality, exact spell id).
function S.Echo(name,q,id,note)
 local card={name=name,quality=q,spellId=id}
 return {text=Nexus.Readout.CardLine(card,nil,nil)..(note and (' '..note) or ''),facts=Nexus.Readout.CardFacts(card)}
end
function S.Paths(o) local out={};for _,p in ipairs(o and o.paths or {}) do out[#out+1]=tostring(p) end return '['..table.concat(out,' ')..']' end
-- The slot of a card that shows an icon: its slot visuals hold exactly one
-- texture, `path`, inside the slot; the slot is inside the row, before the
-- name and apart from the texts; the outline still bears the card's own
-- rarity colour and no other (white 1,1,1 when the quality is unknown).
function S.IconShown(o,path,q)
 if not (o and o.visible and o.rect) then return false,'card not visible' end
 if #o.paths~=1 or o.paths[1]~=path then return false,'slot textures '..S.Paths(o)..', want '..tostring(path) end
 local s,icon=o.slot,nil
 if not (s and G.Inside(s,o.rect,0.01)) then return false,'slot outside its row' end
 for _,v in ipairs(o.visuals) do if v.path==path then icon=S.Rect(v.region) end end
 if not (icon and icon[3]-icon[1]>0 and icon[4]-icon[2]>0 and G.Inside(icon,s,0.01)) then return false,'icon outside the slot' end
 local name=o.texts.name.rect
 if not (name and s[3]<=name[1]+0.01) then return false,'slot '..G.Text(s)..' leaves no space before the name' end
 for _,k in ipairs({'name','quality','tag'}) do
  local t=o.texts[k]
  if t.text~='' and t.rect and not G.Apart(s,t.rect) then return false,'slot '..G.Text(s)..' overlaps the '..k end
 end
 if q and not (S.Only(o,q) and #S.Bearing(o,S.QC[q])>0) then return false,'rarity outline: '..S.Tints(o) end
 if not q and not (S.Rarity(o)==nil and #S.Bearing(o,S.WHITE)>0) then return false,'neutral outline: '..S.Tints(o) end
 return true,'icon '..G.Text(icon)..' in slot '..G.Text(s)
end
-- Whether any region of the card still holds a texture path or id.
function S.Stale(card) for _,p in ipairs(S.Parts(card)) do if SlotSpy.path[p]~=nil then return true end end return false end

C.scenario('REG-ICON-1 the producer keeps the exact spell id of every offer; names and the generated flag are unchanged',function()
 local R=Nexus.Readout
 local board={name='Frostwake Sigil',quality=2,spellId=200001}
 local named=R.CardFacts(board)
 C.expect(type(named)=='table' and named.spellId==200001,'REG-ICON: a named offer\'s facts carry its exact spell id',tostring(type(named)=='table' and named.spellId))
 C.guard(type(named)=='table' and named.name=='Frostwake Sigil' and named.quality==2 and named.generated==nil,'REG-ICON: a named offer keeps its name and quality and is not a generated name')
 local shown=R.OfferCard(R.CardLine(board),false,false,named,false)
 C.guard(shown.name=='Frostwake Sigil' and shown.quality=='Rare','REG-ICON: its card still shows its own name and quality, never its id',tostring(shown.name)..' | '..tostring(shown.quality))
 local nameless=R.CardFacts({quality=2,spellId=200002})
 C.guard(nameless.generated==true and nameless.spellId==200002 and nameless.name=='spell 200002','REG-ICON: a nameless offer keeps its generated name, flag and id')
 local bare=R.CardFacts({name='Hollow Bell',quality=3})
 C.guard(bare.spellId==nil and bare.generated==nil and bare.name=='Hollow Bell','REG-ICON: an offer without a spell id carries none')
 local alike={name='spell 200003',quality=2,spellId=200003}
 local alikeFacts=R.CardFacts(alike)
 C.guard(alikeFacts.generated==nil and R.OfferCard(R.CardLine(alike),false,false,alikeFacts,false).name=='spell 200003',
  'REG-ICON: a supplied name that reads like the fallback is still a supplied name')
end)

C.scenario('REG-ICON-2 an offer with an exact spell id and a verified texture shows that icon; a neighbour without an id borrows none',function()
 local A,B=S.icon.Path(200001),S.icon.Path(200002)
 S.icon.Use({[200001]=A,[200002]=B})
 local m=Model({cards={S.Echo('Frostwake Sigil',2,200001),S.Echo(nil,3,200002,'Owned 1 of 2'),S.Echo('Ashen Crown',4,nil)}})
 P.Render(m)
 for i,want in ipairs({{A,2,'a named offer'},{B,3,'a nameless offer'}}) do
  local o=S.Observe(i)
  if C.setup(o~=nil and o.visible,'REG-ICON: fixture: offer card '..i..' is shown') then
   local ok,why=S.IconShown(o,want[1],want[2])
   C.expect(ok,'REG-ICON: card '..i..' ('..want[3]..') shows the texture of its own spell id inside its slot, before the name, in its rarity outline',why)
   local same,shown,detail=S.Meaning(m,i,o)
   C.guard(same,'REG-ICON: card '..i..' keeps the Readout name, quality and tag',detail)
   local band,bwhy=S.Band(o)
   C.guard(band,'REG-ICON: card '..i..' keeps its compact row in the roll box, its texts inside and apart',bwhy)
   C.guard(S.Edges(o),'REG-ICON: card '..i..' keeps its fixed status edges')
   local tip=V.Plain(table.concat(V.TooltipLines(o.card:GetScript('OnEnter'),o.card),' '))
   C.guard(tip:find(V.Plain(shown.full),1,true)~=nil,'REG-ICON: card '..i..'\'s hover still shows its complete line',tip)
  end
 end
 local third=S.Observe(3)
 if C.setup(third~=nil and third.visible,'REG-ICON: fixture: offer card 3 is shown') then
  local fine,why=S.Fallback(third,4)
  C.guard(fine,'REG-ICON: card 3, without a spell id, keeps its empty rarity slot and shows no neighbour\'s icon',why..' '..S.Paths(third))
 end
 C.expect(S.icon.Asked(200001)==1 and S.icon.Asked(200002)==1,'REG-ICON: each shown offer\'s exact id was looked up once',S.icon.Asked(200001)..'/'..S.icon.Asked(200002))
 S.icon.Restore()
end)

C.scenario('REG-ICON-3 at 50, 100, 125 and 150% the icon stays inside its slot and row beside long names and tags',function()
 S.icon.Use({[200001]=S.icon.Path(200001),[200002]=S.icon.Path(200002),[200003]=S.icon.Path(200003)})
 for _,scale in ipairs({0.5,1,1.25,1.5}) do
  local pct=string.format('%d%%',math.floor(scale*100+0.5))
  P.SetPanelScale(scale)
  P.Render(Model({cards={S.Echo(string.rep('Cinderbound ',8)..'Lattice',2,200001,'Owned 2 of 3'),
   S.Echo('Hollow Bell of the '..string.rep('Ashen ',8)..'Choir',4,200002,'Owned 0 of 1'),
   S.Echo(string.rep('Gravecall ',6)..'Chorus (Rare)',nil,200003,'Owned 1 of 1')}}))
  for i,q in ipairs({2,4,false}) do
   local o=S.Observe(i)
   if C.setup(o~=nil and o.visible,'REG-ICON: fixture: at '..pct..' long card '..i..' is shown') then
    local band,why=S.Band(o)
    C.guard(band,'REG-ICON: at '..pct..' long card '..i..' keeps its compact row with its texts inside and apart',why)
    local ok,iwhy=S.IconShown(o,S.icon.Path(200000+i),q or nil)
    C.expect(ok,'REG-ICON: at '..pct..' long card '..i..' shows its icon inside its slot and row, before the name and apart from its texts',iwhy)
   end
  end
 end
 S.icon.Restore()
 S.Restore()
end)

C.scenario('REG-ICON-4 no id, an id that is not a positive whole number, or a lookup without a texture keeps the empty slot',function()
 local A=S.icon.Path(200001)
 local first=root._offerCards and root._offerCards[1]
 local answers={
  {'no texture in the answer',200011,function() return 'Fixture spell',nil,nil end},
  {'an empty texture',200012,function() return 'Fixture spell',nil,'' end},
  {'false for a texture',200013,function() return 'Fixture spell',nil,false end},
  {'a table for a texture',200014,function() return 'Fixture spell',nil,{} end},
  {'no answer at all',200015,function() return nil end},
  {'a lookup that raises',200016,function() error('fixture: the client lookup failed') end},
 }
 for _,a in ipairs(answers) do
  S.icon.Use({[a[2]]=a[3]})
  local okRender=pcall(P.Render,Model({cards={S.Echo('Frostwake Sigil',2,a[2])}}))
  local o=S.Observe(1)
  if C.setup(okRender and o~=nil and o.visible and o.card==first,'REG-ICON: fixture: the first card is shown after '..a[1]) then
   local fine,why=S.Fallback(o,2)
   C.guard(fine,'REG-ICON: '..a[1]..' keeps the empty rarity slot',why..' '..S.Paths(o))
   C.expect(S.icon.Asked(a[2])==1,'REG-ICON: '..a[1]..': the exact id was asked once, and its failure guessed nothing',S.icon.Asked(a[2]))
  end
 end
 -- An id the client must never be asked about: a texture is on offer for each, so only the refusal keeps the slot empty.
 local huge=2^40
 for _,bad in ipairs({{'zero',0},{'a negative number',-200001},{'a fraction',200001.5},{'a string','200001'},{'a number above the 32-bit range',huge},{'a boolean',true}}) do
  S.icon.Use({[bad[2]]=A,[200001]=A})
  local okRender=pcall(P.Render,Model({cards={S.Echo('Frostwake Sigil',3,bad[2])}}))
  local o=S.Observe(1)
  if C.setup(okRender and o~=nil and o.visible and o.card==first,'REG-ICON: fixture: the first card is shown with '..bad[1]..' as its spell id') then
   local fine,why=S.Fallback(o,3)
   C.guard(fine and #S.icon.calls==0,'REG-ICON: '..bad[1]..' as a spell id is never looked up and keeps the empty rarity slot',why..' '..S.Paths(o)..' lookups '..#S.icon.calls)
  end
 end
 S.icon.Use({[200001]=A})
 P.Render(Model({cards={{text='Frostwake Sigil (Rare)'}}}))
 local plain=S.Observe(1)
 C.guard(plain~=nil and plain.visible and (S.Fallback(plain,nil)) and #S.icon.calls==0,'REG-ICON: a card without facts is never looked up, whatever its text names',S.Paths(plain))
 GetSpellInfo=nil
 local okNone=pcall(P.Render,Model({cards={S.Echo('Frostwake Sigil',2,200001)}}))
 GetSpellInfo=S.icon.Lookup
 local none=S.Observe(1)
 C.guard(okNone and none~=nil and none.visible and (S.Fallback(none,2)),'REG-ICON: a client without the lookup renders the empty rarity slot',S.Paths(none))
 S.icon.Restore()
end)

C.scenario('REG-ICON-5 one reused card: another id under the same name, a failed lookup, no offer and a returning offer keep no earlier texture',function()
 local A,B=S.icon.Path(200001),S.icon.Path(200002)
 S.icon.Use({[200001]=A,[200002]=B})
 local first=root._offerCards and root._offerCards[1]
 -- Another board first: the scenario before this one ended on this same offer
 -- with no lookup available, and a settled render asks nothing (REG-ICON-6).
 P.Render(Model())
 P.Render(Model({cards={S.Echo('Frostwake Sigil',2,200001)}}))
 local o1=S.Observe(1)
 if not C.setup(o1~=nil and o1.visible and o1.card==first,'REG-ICON: fixture: the first card is shown') then S.icon.Restore();return end
 local a,awhy=S.IconShown(o1,A,2)
 local parts=#S.Parts(first)
 C.expect(a,'REG-ICON: the first card shows the texture of spell 200001',awhy)
 P.Render(Model({cards={S.Echo('Frostwake Sigil',2,200002)}}))
 local o2=S.Observe(1)
 local b,bwhy=S.IconShown(o2,B,2)
 C.guard(o2.card==first and o2.texts.name.text==o1.texts.name.text and o2.texts.quality.text==o1.texts.quality.text and o2.texts.tag.text==o1.texts.tag.text,
  'REG-ICON: fixture: the second offer reads exactly like the first (same name, quality and tag)')
 C.expect(b,'REG-ICON: the same visible name with another spell id shows that id\'s texture, not the earlier one',bwhy)
 P.Render(Model({cards={S.Echo('Frostwake Sigil',2,200019)}}))
 local o3=S.Observe(1)
 local c,cwhy=S.Fallback(o3,2)
 C.expect(a and b and c and S.icon.Asked(200019)==1,'REG-ICON: after two icons, an id without a texture puts the empty rarity slot back on the same card',cwhy..' '..S.Paths(o3))
 P.Render(Model({cards={S.Echo('Frostwake Sigil',2,200001)}}))
 local again=S.IconShown(S.Observe(1),A,2)
 P.Render(Model({cards={},recommendation=''}))
 C.expect(again and not first:IsVisible() and not S.AnyVisible(first) and not S.Stale(first),
  'REG-ICON: with no offer the card that showed an icon is hidden with everything in it and holds no texture')
 P.Render(Model({cards={S.Offer('Hollow Bell',3)}}))
 local o5=S.Observe(1)
 local e,ewhy=S.Fallback(o5,3)
 C.guard(o5.card==first and e and not S.Stale(first),'REG-ICON: a returning offer without a spell id shows its empty rarity slot, no earlier icon',ewhy..' '..S.Paths(o5))
 P.Render(Model({cards={S.Echo('Frostwake Sigil',2,200001)}}))
 local f,fwhy=S.IconShown(S.Observe(1),A,2)
 C.expect(f,'REG-ICON: a returning offer with a spell id shows its texture again',fwhy)
 C.guard(#S.Parts(first)==parts,'REG-ICON: the reused card keeps the same slot regions (none added per render)',parts..' -> '..#S.Parts(first))
 S.icon.Restore()
end)

C.scenario('REG-ICON-6 one lookup per shown offer per layout pass, none on a settled render, and no failure is remembered',function()
 local D=S.icon.Path(200004)
 S.icon.Use({[200001]=S.icon.Path(200001),[200002]=S.icon.Path(200002),[200003]=S.icon.Path(200003)})
 local function Three() return Model({cards={S.Echo('Frostwake Sigil',2,200001),S.Echo('Hollow Bell',3,200002),S.Echo('Ashen Crown',4,200003)}}) end
 local function Asked() return S.icon.Asked(200001)..'/'..S.icon.Asked(200002)..'/'..S.icon.Asked(200003)..' of '..#S.icon.calls end
 P.Render(Model())
 S.icon.calls={}
 local l0=P.RenderStats().layouts
 P.Render(Three())
 C.expect(P.RenderStats().layouts==l0+1 and Asked()=='1/1/1 of 3','REG-ICON: the layout pass that shows three offers asks once for each exact id and for nothing else',Asked())
 S.icon.calls={}
 local l1=P.RenderStats().layouts
 P.Render(Three());P.Render(Three())
 local shown=true
 for i=1,3 do shown=shown and (S.IconShown(S.Observe(i),S.icon.Path(200000+i),({2,3,4})[i])) end
 C.expect(shown and P.RenderStats().layouts==l1 and #S.icon.calls==0,'REG-ICON: two settled renders of the same offers keep the three icons and look nothing up',Asked())
 local function Late(rec) return Model({cards={S.Echo('Cinder Lattice',1,200004)},recommendation=rec}) end
 S.icon.calls={}
 P.Render(Late())
 local o=S.Observe(1)
 local empty,why=S.Fallback(o,1)
 C.expect(empty and S.icon.Asked(200004)==1,'REG-ICON: an id the client has no texture for is asked once and keeps the empty rarity slot',why..' asked '..S.icon.Asked(200004))
 S.icon.map[200004]=D
 S.icon.calls={}
 P.Render(Late())
 C.guard((S.Fallback(S.Observe(1),1)) and #S.icon.calls==0,'REG-ICON: a settled render of that offer asks nothing more',#S.icon.calls)
 P.Render(Late('Take Cinder Lattice.'))
 local late,lwhy=S.IconShown(S.Observe(1),D,1)
 C.expect(late and S.icon.Asked(200004)==1,'REG-ICON: the next layout pass asks again and shows the texture: the earlier failure was not kept',lwhy..' asked '..S.icon.Asked(200004))
 S.icon.Restore()
end)

C.scenario('REG-ICON-7 a card that shows an icon stays passive: no handler of its own, a click does nothing, the Shift drag still works',function()
 S.icon.Use({[200001]=S.icon.Path(200001)})
 local m=Model({cards={S.Echo('Frostwake Sigil',2,200001)}})
 P.Render(m)
 local card=root._offerCards and root._offerCards[1]
 if not C.setup(card~=nil and card:IsVisible() and P._panelDrag==nil,'REG-ICON: fixture: a visible offer card and no active move') then S.icon.Restore();return end
 local o=S.Observe(1)
 C.expect((S.IconShown(o,S.icon.Path(200001),2)),'REG-ICON: fixture: the card shows its icon')
 local up=root:GetScript('OnMouseUp')
 Reset()
 local before=Effects()
 local plain=true
 for _,p in ipairs(S.Parts(card)) do
  local kind=p.GetObjectType and p:GetObjectType()
  if kind~='Texture' then plain=false end
 end
 C.guard(plain,'REG-ICON: the slot and its icon are plain textures of the card: no frame, button or mouse region of their own')
 C.guard(card:GetScript('OnClick')==nil and card:GetScript('OnMouseUp')==nil and card._nexusPassiveDrag==true,
  'REG-ICON: the card chooses nothing: no click or mouse-up of its own; it is a passive drag surface')
 local okClick=pcall(function() card:Click('LeftButton');if up then up(root,'LeftButton') end end)
 C.guard(okClick and Move.starts==0 and Move.stops==0 and P._panelDrag==nil and Effects()==before,'REG-ICON: an ordinary click on the card moves, saves and sends nothing',Effects())
 ShiftHeld.value=true
 local start=card:GetScript('OnDragStart')
 local stop=card:GetScript('OnDragStop')
 local okA=start~=nil and (pcall(start,card,'LeftButton'))
 local active=P._panelDrag~=nil and P._panelDrag.origin==card and Move.starts==1
 local okB=stop~=nil and (pcall(stop,card))
 C.guard(okA and okB and active and P._panelDrag==nil and Move.stops==1,'REG-ICON: with Shift held a left drag from the card starts and its release ends one move')
 if P._panelDrag and up then pcall(up,root,'LeftButton') end
 ShiftHeld.value=1
 Reset()
 C.guard(Effects()==before,'REG-ICON: the icon checks change no action, send, ownership or slot request, saved data or Auto',Effects())
 S.icon.Restore()
 S.Restore()
end)
-- Whatever a REG-ICON scenario left: the client lookup is the harness's again.
S.icon.Restore()

C.scenario('REG-SLOT-5 after the offer checks: nothing else changed and unrelated textures keep their identity',function()
 S.Restore()
 C.guard(P._panelDrag==nil and ShiftHeld.value==1,'REG-SLOT: no move is active and Shift is held again for the later scenarios')
 C.guard(Effects()==S.keep.effects,'REG-SLOT: no action, send, ownership or slot request, saved data or Auto changed',Effects())
 C.guard(CB.refresh==S.keep.cb[1] and CB.toggle==S.keep.cb[2],'REG-SLOT: no refresh step or Auto toggle ran')
 local changed=0
 for r,t in pairs(S.keep.textures) do if r:GetTexture()~=t then changed=changed+1 end end
 C.guard(changed==0,'REG-SLOT: every texture path outside the offer cards is unchanged',changed)
 local mm,found=_G.NexusMinimapButton,false
 for _,t in pairs(S.keep.textures) do if t=='Interface\\AddOns\\Nexus\\ui\\Textures\\NexusMinimap.tga' then found=true end end
 C.guard(mm==nil or found,'REG-SLOT: the minimap button keeps its verified Nexus icon')
end)

-- REG-SLOT cleanup before V4 (which rebinds RM and boots again): test-local
-- state back, then the observed methods returned as they were (absent ones
-- absent again).
pcall(S.Restore)
SlotSpy.methods.SetTexture=SlotSpy.saved.SetTexture
SlotSpy.methods.SetVertexColor=SlotSpy.saved.SetVertexColor

-- V4 last: it loads the addon again (a fresh load) with the saved data.
C.scenario('V4 a centre saved at a fitted size is kept on a fresh load',function()
 UIParent:SetSize(640,1080)
 P.SetPanelScale(1.5)
 P.Render(Model())
 local r=616/420
 C.setup(math.abs(root:GetScale()-r)<0.0005,'V4: fixture: 150% is reduced to fit a 640-wide screen',root:GetScale())
 Reset()
 Start(root._contextBuildHit)
 Move.x,Move.y=300,330
 Stop(root._contextBuildHit)
 local sx,sy=Saved()
 C.setup(sx==math.floor(300*r-960+0.5) and sy==math.floor(330*r-540+0.5),'V4: fixture: the drag saved its centre in UIParent units',
  tostring(sx)..','..tostring(sy))
 local db=NexusDB
 H=F.Boot(db,function(h) F.OrbService(h) end)
 P,LM=Nexus.Panel,Nexus.LayoutMetrics
 RM=G.RegionMethods()
 RM.GetEffectiveScale=function(self)
  local parent=self.parent
  return (self.scale or 1)*(parent and parent.GetEffectiveScale and parent:GetEffectiveScale() or 1)
 end
 UIParent:SetSize(640,1080)
 local saved=F.Serialize(NexusDB)
 P.Show()
 C.setup(P.Render(Model())==true,'V4: fixture: the panel renders after the fresh load')
 local fresh=NexusPanel
 local s=fresh:GetScale()
 local p,rel,relP,x,y=fresh:GetPoint(1)
 C.expect(math.abs(s-r)<0.0005 and fresh:GetNumPoints()==1 and p=='CENTER' and rel==UIParent and relP=='CENTER'
  and math.abs(x*s-sx)<0.5 and math.abs(y*s-sy)<0.5,
  'V4: after a fresh load the saved centre is the centre at the fitted size',
  tostring(p)..' '..tostring(x and x*s)..','..tostring(y and y*s)..' at '..s)
 C.guard(F.Serialize(NexusDB)==saved,'V4: the fresh load writes no position, size or other saved data')
end)

-- Held-Shift fixture scope ends: the query saved before the drag helpers returns.
IsShiftKeyDown=RealIsShiftKeyDown

Nexus.DisableOrdinaryAutomation()
C.finish('(review corrections over the harness with modelled hide propagation, effective scale and tooltip owner; native NOT RUN)')
