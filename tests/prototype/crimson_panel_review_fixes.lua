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
-- REG-ROW adds, the same way: the colour a text receives through
-- SetTextColor(r,g,b[,a]) and the vertical justification it is given.
local SlotSpy={methods=RM,saved={SetTexture=rawget(RM,'SetTexture'),SetVertexColor=rawget(RM,'SetVertexColor'),
  SetTextColor=rawget(RM,'SetTextColor'),SetJustifyV=rawget(RM,'SetJustifyV')},
 fill=setmetatable({},{__mode='k'}),vertex=setmetatable({},{__mode='k'}),path=setmetatable({},{__mode='k'}),
 text=setmetatable({},{__mode='k'}),justify=setmetatable({},{__mode='k'})}
RM.SetTextColor=function(self,...)
 local a,b,c=...
 if type(a)=='number' and type(b)=='number' and type(c)=='number' then SlotSpy.text[self]={a,b,c} end
 local prev=SlotSpy.saved.SetTextColor
 if prev then return prev(self,...) end
end
RM.SetJustifyV=function(self,...)
 SlotSpy.justify[self]=(...)
 local prev=SlotSpy.saved.SetJustifyV
 if prev then return prev(self,...) end
end
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
 -- Approved panel cleanup ("Full ... recommendation and reason text. Wrap and
 -- grow ... No clipping, ellipsis or arbitrary line cap"): a long
 -- recommendation no longer overflows a fixed box with its complete text only
 -- on a hover. Its box is as tall as its wrapped text, so the complete text
 -- is on the panel itself.
 local rec=root._rollRec
 C.guard(V.Plain(rec:GetText() or ''):find('Take the needed Echo when it is offered.',1,true)~=nil
  and rec:GetHeight()+0.5>=rec:GetStringHeight(),'V2: the complete recommendation is shown on the panel, in a box as tall as its wrapped text',
  rec:GetHeight()..' needs '..rec:GetStringHeight())
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

-- REG-SLOT (S3_OFFER_EMPTY_SLOT / MI-F01, as corrected by REG-ROW): an offer
-- whose Echo has no verified icon shows NO icon: nothing in its row shows or
-- holds a texture path or id, and its name is in the Echo rarity colour of
-- the card's own quality (OrbHistory.QUALITY_COLORS); an unknown own quality,
-- a name ending in "(Rare)" included, stays white. These model cards carry no
-- spell id (REG-ICON below covers those that do). What a row shows is read
-- from the card's real region tree apart from its fill and three texts, and
-- from what SetTexture / SetVertexColor / SetTextColor received (SlotSpy).
-- The rarity-tinted outline of the empty slot and the row's status edges,
-- which these scenarios required to 89124b3a, are removed on the user's
-- request ("remove the outline boxes"); REG-ROW expects their absence: no
-- icon and no row that is not selected has an outline. The selected row's
-- accent outline is the main-panel visual correction's own (REG-ROW,
-- S.Outline). GUARD here: current text, tag, hover, band, hidden cards, the
-- name's colour, passive input and the Shift drag; EXPECT: each row as tall
-- as its content needs (S.Lines: the approved compact row; the rows were
-- the two-line grid before it and one line before that). Model geometry
-- only: native pixel fit and desktop 125% are NOT RUN.
local S={QC=Nexus.OrbHistory and Nexus.OrbHistory.QUALITY_COLORS or {}}
function S.Offer(name,q,note)
 local qn=q and Nexus.OrbHistory.QUALITY_NAMES[q]
 return {text=name..(qn and (' ('..qn..')') or '')..(note and (' '..note) or ''),facts=Nexus.Readout.CardFacts({name=name,quality=q})}
end
function S.Same(c,q)
 return type(c)=='table' and type(q)=='table' and math.abs(c[1]-q[1])<0.001 and math.abs(c[2]-q[2])<0.001 and math.abs(c[3]-q[3])<0.001
end
function S.Rect(r) local ok,v=pcall(G.Rect,r,root);return ok and v or nil end
-- The card's own descendants apart from its fill and three texts, each once:
-- the harness lists a created Texture or FontString both as a region and as
-- a child (as G.Shown notes), so both routes use the same skip and seen sets.
-- Unknown descendants are kept; frames are walked into. A row outline, were
-- one painted again, is among them (REG-ROW).
function S.Parts(card)
 local skip,seen,out={},{},{}
 for _,k in ipairs({'fill','name','quality','tag'}) do if card[k] then skip[card[k]]=true end end
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
-- The row's dark ground (card.fill). Since the main-panel visual correction
-- it is a texture of the roll area on the row's box, drawn under the reason
-- that stands inside the selected row, so the walk above, which covered it
-- while it was the card's own region, no longer reaches it. A hidden card's
-- ground must be hidden with it, as before.
function S.GroundShown(card) return card.fill~=nil and card.fill:IsVisible() and true or false end
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
S.WHITE={1,1,1}
-- The colour the card's name last received: its own Echo rarity colour, or
-- white 1,1,1 when its quality is unknown.
function S.Named(o,q)
 local c=SlotSpy.text[o.card.name]
 return S.Same(c,q and S.QC[q] or S.WHITE),c and string.format('name colour %.2f/%.2f/%.2f',c[1],c[2],c[3]) or 'name colour never set'
end
function S.Paths(o) local out={};for _,p in ipairs(o and o.paths or {}) do out[#out+1]=tostring(p) end return '['..table.concat(out,' ')..']' end
-- Whether any region of the card still holds a texture path or id.
function S.Stale(card) for _,p in ipairs(S.Parts(card)) do if SlotSpy.path[p]~=nil then return true end end return false end
-- An offer without a verified icon: its row is shown, nothing in it shows or
-- holds a texture path or id, and its name is in its own rarity colour.
function S.Fallback(o,q)
 if not (o and o.visible and o.rect) then return false,'card not visible' end
 if #o.paths>0 or S.Stale(o.card) then return false,'a texture '..S.Paths(o) end
 return S.Named(o,q)
end
-- The rectangle of the one texture path or id the row shows.
function S.Icon(o)
 for _,v in ipairs(o and o.visuals or {}) do if v.path~=nil then return S.Rect(v.region) end end
 return nil
end
-- REG-ROW: the numbers the rows are built from.
-- The approved compact panel (design draft "Nexus compact panel") replaces
-- the two-line grid row (the name over its quality, the tag in a status
-- column; 29 units at the reference lines) by the compact row. The draft is
-- drawn in reference pixels, 420 across the panel that is 284 units wide at
-- the reference text size, so one of its pixels is 284 / 420 unit x the
-- layout's font scale; S.L gives its row lengths in whole units, stated
-- here from the draft and not read back from the product: the content is
-- inset 6 pixels from both ends with 2 pixels above and below; the icon is
-- a 24-pixel square on the row's first line (24 pixels), 8 pixels before
-- the text column; at the row's right end stands the phrase: the quality,
-- a dot (5 pixels either side) and the status, a selected status after its
-- 12-pixel star and 4; 10 pixels separate a name and a phrase on one line;
-- the selected offer's reason is a line of 18 pixels inside its row.
function S.L()
 local l=root._responsiveLayout
 local unit=284/420*(tonumber(l.scale) or 1)
 local function D(px) return math.max(1,math.floor(px*unit+0.5)) end
 -- (rowGap: the 2 pixels between two rows, which a row's thin outline
 -- edge is never thicker than.)
 return {small=l.small,normal=l.normal,gap=l.gap,unit=unit,D=D,pad=D(2),rowGap=D(2),inset=D(6),icon=D(24),line=D(24),
  textX=D(6)+D(24)+D(8),meta=D(10),word=D(5),mark=D(12),markGap=D(4),reason=D(18)}
end
-- Whether `units` is a length the draft gives as `px` pixels, where it
-- stands (a block's own place decides whether it rounds down or up).
function S.Drawn(px,units)
 local unit=S.L().unit
 return math.abs(units-math.floor(px*unit))<0.01 or math.abs(units-math.ceil(px*unit))<0.01
end
-- One row as the draft arranges it, worked out from the row's own words in
-- the font model in use; nothing is read from the panel's arrangement.
--   inline: the name, 10 pixels and the phrase fit the text column on one
--   line (the draft's 28-pixel row);
--   under: otherwise the name has the column, wrapping there, and the
--   phrase stands on a line of its own under it (24 pixels more);
--   split: a phrase wider than the column stands as its two parts under the
--   name, the quality and under it the status, without the dot (24 pixels
--   each), a part wider than the column (the status: less its star)
--   wrapping there.
-- `need` is what the row's content needs in units and `pixels` the draft's
-- own height for the arrangement.
function S.Plan(card)
 local L=S.L()
 local char,line=G.model.char,math.ceil(G.model.line)
 local function W(t) local s=G.Visible(t:GetText() or '');return s~='' and math.ceil(G.Length(s)*char) or 0 end
 local function H(t,room) return math.max(1,G.Rows(t:GetText() or '',room,char))*line end
 local p={column=card:GetWidth()-L.textX-L.inset,nameW=W(card.name),qualityW=W(card.quality),tagW=W(card.tag)}
 p.selected=card._nexusMarked==true or S.GroundShown(card)
 p.dotW=(p.qualityW>0 and p.tagW>0) and (2*L.word+math.ceil(char)) or 0
 p.starW=(p.tagW>0 and p.selected) and (L.mark+L.markGap) or 0
 p.phrase=p.qualityW+p.dotW+p.starW+p.tagW
 p.inline=p.phrase==0 or p.nameW+L.meta+p.phrase<=p.column
 p.split=p.phrase>p.column
 local under,lines=0,0
 if p.split then
  if p.qualityW>0 then under,lines=under+math.max(L.line,H(card.quality,p.column)),lines+1 end
  if p.tagW>0 then under,lines=under+math.max(L.line,H(card.tag,p.column-p.starW)),lines+1 end
 elseif not p.inline then
  under,lines=math.max(L.line,line),1
 end
 p.first=p.inline and line or H(card.name,p.column)
 p.under,p.need,p.pixels=under,2*L.pad+p.first+under,28+24*lines
 return p
end
-- A row whose name and phrase fit one line: the draft's 28 pixels where it
-- stands, never under what its one measured line and its pads need (it was
-- the two-line grid row: a line of name over a line of quality).
function S.BaseRow(height)
 local L=S.L()
 local need=2*L.pad+math.ceil(G.model.line)
 return height>=need and (height==need or S.Drawn(28,height))
end
-- The appearance's roles (approved: "apply existing theme text/muted/accent
-- roles explicitly"), from the appearance's own resolved tables, never
-- restated here: ordinary text, muted text and the palette's accent.
function S.Roles()
 local chosen=Nexus.Theme.Resolve(NexusDB.settings.uiStyle,NexusDB.settings.uiPalette)
 return {text=chosen.style.text,muted=chosen.style.disabledText,accent=chosen.palette.accent}
end
-- What a row paints besides its three texts and its icon (approved:
-- "selected accent outline/dark fill"). `selected` is the scenario's own
-- statement of whether this is the selected row; it is never read from the
-- panel.
--   A row that is not selected paints and shows nothing else: no outline
--   edge, no bar and no fill.
--   The selected row shows a dark fill on its own box and exactly four
--   painted colour regions, all in the appearance's accent: thin lines (no
--   thicker than a row gap) on the row's own four edges, two across its
--   whole width at its top and bottom and two down its whole height at its
--   left and right. A fifth region, a region off those edges, another
--   colour or the former 2-unit accent bar fails, and so does an outline on
--   a row that is not selected or anything painted around an icon.
-- Approved panel cleanup had the selected row as a filled band with one
-- 2-unit accent bar and no outline; S.Bare held that until this correction.
function S.Outline(o,selected)
 if o==nil then return false,'no row' end
 local painted={}
 for _,v in ipairs(o.visuals or {}) do if v.path==nil then painted[#painted+1]=v end end
 local fill=o.card.fill
 local filled=fill~=nil and fill:IsVisible() and true or false
 if not selected then
  if #painted>0 or filled then
   local r=painted[#painted] and S.Rect(painted[#painted].region) or nil
   return false,#painted..' painted colour region(s) besides the icon'..(filled and ' and a fill' or '')..(r and (' '..G.Text(r)) or '')
  end
  return true,'0 painted colour region(s) and no fill'
 end
 local L,r,accent=S.L(),o.rect,S.Roles().accent
 local fr=filled and S.Rect(fill) or nil
 local dark=fill~=nil and SlotSpy.fill[fill] or nil
 if not (fr and r and math.abs(fr[1]-r[1])<0.01 and math.abs(fr[2]-r[2])<0.01 and math.abs(fr[3]-r[3])<0.01
  and math.abs(fr[4]-r[4])<0.01 and type(dark)=='table' and dark[1]<=0.2 and dark[2]<=0.2 and dark[3]<=0.2) then
  return false,'the selected row has no dark fill on its own box'..(fr and (' '..G.Text(fr)) or '')
 end
 if #painted~=4 then return false,#painted..' painted colour region(s) besides the fill, want its four outline edges' end
 local sides={top=0,bottom=0,left=0,right=0}
 for _,v in ipairs(painted) do
  local e=S.Rect(v.region)
  if not (e and S.Same(v.fill or v.vertex,accent)) then
   return false,'an outline edge'..(e and (' '..G.Text(e)) or '')..' is not in the appearance\'s accent colour'
  end
  local across=math.abs(e[1]-r[1])<0.01 and math.abs(e[3]-r[3])<0.01 and e[4]-e[2]<=L.rowGap+0.01
  local down=math.abs(e[2]-r[2])<0.01 and math.abs(e[4]-r[4])<0.01 and e[3]-e[1]<=L.rowGap+0.01
  if across and math.abs(e[2]-r[2])<0.01 then sides.top=sides.top+1
  elseif across and math.abs(e[4]-r[4])<0.01 then sides.bottom=sides.bottom+1
  elseif down and math.abs(e[1]-r[1])<0.01 then sides.left=sides.left+1
  elseif down and math.abs(e[3]-r[3])<0.01 then sides.right=sides.right+1
  else return false,'a painted region '..G.Text(e)..' is not a thin line on an edge of its row '..G.Text(r) end
 end
 if not (sides.top==1 and sides.bottom==1 and sides.left==1 and sides.right==1) then
  return false,'the outline is not one line on each edge (top '..sides.top..', bottom '..sides.bottom..', left '..sides.left..', right '..sides.right..')'
 end
 return true,'the accent outline on its four edges over the dark fill'
end
-- The borderless icon: the draft's 24-pixel square (S.L().icon) at the
-- row's left inset, 2 pixels under its top, on the row's first line. A row
-- whose text wraps is taller, and the icon keeps that square beside the
-- first line instead of growing with the row. (It was a square as tall as
-- the grid row's two text lines, one row gap under the row's top.)
function S.IconFit(o)
 local icon,r=S.Icon(o),o.rect
 if not icon then return false,'no icon' end
 local L=S.L()
 local side=icon[3]-icon[1]
 if math.abs(side-(icon[4]-icon[2]))>0.01 or math.abs(side-L.icon)>0.01 then
  return false,'icon '..G.Text(icon)..' is not the draft\'s 24-pixel square '..L.icon..' in '..G.Text(r)
 end
 if math.abs(icon[1]-(r[1]+L.inset))>0.01 or math.abs(icon[2]-(r[2]+L.pad))>0.01 then
  return false,'icon '..G.Text(icon)..' is not at the left inset, 2 pixels under the top, of its row '..G.Text(r)
 end
 return true,G.Text(icon)
end
-- The places of one row's texts (the approved compact row): the name starts
-- at the text column, 8 pixels after the icon's square (kept free without an
-- icon, so names stay aligned), 2 pixels under the row's top. The phrase
-- ends at the row's right inset: on one line the quality stands before the
-- status with the dot between them, on the name's line while S.Plan says
-- they fit it and under the name otherwise; a split phrase has the quality
-- under the name and the status under the quality. Every shown text stays
-- inside the row's pads. A one-line text stands in the middle of its line
-- and a text taller than the row's line starts at its top. (The grid row had
-- the quality under the name in the name's column and the status word in a
-- column of its own, every text set to the top of its box.)
function S.Columns(o)
 local L,r=S.L(),o.rect
 local name,quality,tag=o.texts.name,o.texts.quality,o.texts.tag
 local plan=S.Plan(o.card)
 local x,right=r[1]+L.textX,r[3]-L.inset
 if not name.rect then return false,'name has no box' end
 if math.abs(name.rect[1]-x)>0.01 then return false,string.format('name starts at %.1f, want %.1f',name.rect[1],x) end
 if math.abs(name.rect[2]-(r[2]+L.pad))>0.01 then
  return false,'name '..G.Text(name.rect)..' is not 2 pixels under the top of its row '..G.Text(r)
 end
 if quality.text~='' and not quality.rect then return false,'quality has no box' end
 if tag.text~='' and not tag.rect then return false,'tag has no box' end
 local last=tag.text~='' and tag.rect or (quality.text~='' and quality.rect or nil)
 if last and math.abs(last[3]-right)>0.01 then return false,string.format('the phrase ends at %.1f, want %.1f',last[3],right) end
 local first=quality.text~='' and quality.rect or (tag.text~='' and tag.rect or nil)
 if plan.inline then
  if first and (first[1]<name.rect[3]+L.meta-0.01 or math.abs(first[2]-name.rect[2])>0.01) then
   return false,'the phrase '..G.Text(first)..' is not on the line of its name '..G.Text(name.rect)..', 10 pixels after it'
  end
  if (name.rect[3]-name.rect[1])<plan.nameW-0.01 then return false,'the name\'s box is narrower than its words' end
 else
  if math.abs((name.rect[3]-name.rect[1])-plan.column)>0.01 then
   return false,string.format('the name is %.1f wide, want the text column %.1f',name.rect[3]-name.rect[1],plan.column)
  end
  if first and first[2]<name.rect[4]-0.01 then return false,'the phrase '..G.Text(first)..' is not under its name '..G.Text(name.rect) end
 end
 if quality.text~='' and tag.text~='' then
  if plan.split then
   if tag.rect[2]<quality.rect[4]-0.01 or math.abs(quality.rect[3]-right)>0.01 or o.card.dot:IsShown() then
    return false,'a split phrase: the status '..G.Text(tag.rect)..' is not under its quality '..G.Text(quality.rect)..' with no dot'
   end
  elseif quality.rect[3]>tag.rect[1]+0.01 or math.abs(quality.rect[2]-tag.rect[2])>0.01 or not o.card.dot:IsShown() then
   return false,'the quality '..G.Text(quality.rect)..' is not before the status '..G.Text(tag.rect)..' on one line with the dot between them'
  end
 end
 if (o.card.star:IsShown() and true or false)~=(plan.starW>0) then
  return false,'star shown '..tostring(o.card.star:IsShown())..' for a selected status '..tostring(plan.starW>0)
 end
 for _,k in ipairs({'name','quality','tag'}) do
  local t=o.texts[k]
  if t.text~='' then
   if t.rect[2]<r[2]+L.pad-0.01 or t.rect[4]>r[4]-L.pad+0.01 then
    return false,k..' '..G.Text(t.rect)..' is not inside the pads of its row '..G.Text(r)
   end
   -- The name: taller than the row's line, from its top. A part of the
   -- phrase: wrapped to more than one line, from its top; else in the
   -- middle of its line.
   local tall
   if k=='name' then tall=o.card[k]:GetStringHeight()>L.line+0.01
   else tall=o.card[k]:GetStringHeight()>math.ceil(G.model.line)+0.01 end
   local want=tall and 'TOP' or 'MIDDLE'
   if SlotSpy.justify[o.card[k]]~=want then
    return false,k..' is set to '..tostring(SlotSpy.justify[o.card[k]])..', want '..want
   end
  end
 end
 return true,G.Text(r)
end
-- The band (the approved compact rows): the first row the draft's 3 pixels
-- under the heading row, each row 2 pixels from the next, and the text under
-- the rows 3 pixels below the last. The heading row is as tall as its box
-- (one line of the heading, or a heading that is measured taller or wraps).
-- A row is exactly as tall as its content needs (S.Plan: its pads, its
-- name's measured lines and the phrase's lines under them), or the draft's
-- own height for its arrangement when the content needs no more (approved:
-- "Equal base row rhythm must grow for full real text/reason, never
-- line-clamp or omit it"). (The grid row was the name's lines over the
-- quality's, never under 29 units, two row gaps under the heading.)
-- `selected` is the scenario's own statement of which row is the selected
-- offer (nil: none); it is never read from the panel, so the panel cannot
-- choose which of the two contracts below is checked.
--   No selected row: the text under the rows starts 3 pixels below the last
--   row. This check is unconditional and fails when that text has no box.
--   Selected row i: its reason is inside it, once: under the row's own
--   lines, at the text column's left edge, ending no later than the row's
--   right inset and 2 pixels above the row's bottom; the row is 18 pixels
--   taller for it, or by the reason's own measured lines when they need
--   more.
function S.Rows(n,selected)
 local L,roll=S.L(),S.Rect(root._rollArea)
 local head=root._rollStatus
 local bottom=roll[2]+(head and head:IsShown() and head:GetHeight() or 0)
 local top
 local rec=S.Rect(root._rollRec)
 for i=1,n do
  local card=root._offerCards[i]
  local r=card:IsVisible() and S.Rect(card) or nil
  if not r then return false,'row '..i..' is not shown' end
  local plan=S.Plan(card)
  local need,pixels=plan.need,plan.pixels
  if i==selected then
   if G.Visible(root._rollRec:GetText() or '')=='' or not rec then return false,'the selected row '..i..' has no reason text with a box' end
   local lines=r[2]+L.pad+plan.first+plan.under
   if rec[2]<lines-0.01 or math.abs(r[4]-rec[4]-L.pad)>0.01 or math.abs(rec[1]-(r[1]+L.textX))>0.01
    or rec[3]>r[3]-L.inset+0.01 then
    return false,string.format('the selected row %d %s holds its reason at %s, want it from %.1f or lower to %.1f in the text column',
     i,G.Text(r),G.Text(rec),lines,r[4]-L.pad)
   end
   need,pixels=need+math.max(L.reason,math.ceil(root._rollRec:GetStringHeight() or 0)),pixels+18
  end
  local height=r[4]-r[2]
  if not S.Drawn(i==1 and 3 or 2,r[2]-bottom) then
   return false,string.format('row %d %s starts %.1f under what stands above it, want the draft\'s %d pixels',i,G.Text(r),r[2]-bottom,i==1 and 3 or 2)
  end
  if height<need-0.01 or not (math.abs(height-need)<0.01 or S.Drawn(pixels,height)) then
   return false,string.format('row %d %s, want its content\'s %.1f or the draft\'s %d pixels',i,G.Text(r),need,pixels)
  end
  top=top or r[2]
  bottom=r[4]
 end
 if not selected and not (rec and S.Drawn(3,rec[2]-bottom)) then
  return false,string.format('the text under the rows starts at %.1f, want the draft\'s 3 pixels under %.1f',rec and rec[2] or -1,bottom)
 end
 return true,string.format('rows from %.1f, %s',top or -1,selected and ('the reason inside row '..selected) or string.format('text %.1f under them',rec[2]-bottom))
end
-- The room the text under the rows had while they were one-line rows (to
-- test.163021): the roll box's least height less the heading, three rows and
-- the box's bottom gap. More rows of guidance only add to it.
-- Approved panel cleanup ("Save height through spacing and conditional
-- content"; no fixed empty block): the text under the rows no longer keeps
-- the room of the former fixed 104-unit box whether it needs it or not. What
-- is protected now is that its box is inside the roll box and as tall as the
-- text it holds needs.
function S.BodyRoom()
 local text=root._rollRec
 local rec,roll=S.Rect(text),S.Rect(root._rollArea)
 local needs=G.Visible(text:GetText() or '')~='' and text:GetStringHeight() or 0
 return rec~=nil and roll~=nil and G.Inside(rec,roll,0.01) and (rec[4]-rec[2])+0.5>=needs,
  string.format('%.1f for a text that needs %.1f',rec and rec[4]-rec[2] or -1,needs)
end
-- The row's words against the Readout's own card. The approved compact row
-- shows a selected tag's words after its star in place of the code-owned
-- mark before them. An unselected row shows the short "Wrong quality" status
-- only where its model card itself carries a "different quality" annotation
-- code (`annotation`: the Policy's 'wrong quality' or 'low quality') and is
-- not a guaranteed offer; a card that carries only its line keeps its
-- complete annotation on the row, whatever that annotation's words are. In
-- every case the Readout's whole tag stays the row's own, for its hover.
function S.Meaning(model,i,o)
 local R=Nexus.Readout
 local cards=model.cards
 local marked=R.MarkedCard and R.MarkedCard(cards) or nil
 local frozen=model.auto==false and not marked and R.FreezeCard and R.FreezeCard(cards) or nil
 local c=cards[i]
 local shown=R.OfferCard(c.text,marked==i,model.auto,type(c.facts)=='table' and c.facts or nil,frozen==i)
 local tag,starred=tostring(shown.shown or shown.tag),false
 if (shown.marked or shown.freeze) and tag:sub(1,2)=='> ' and #tag>2 then
  tag,starred=tag:sub(3),true
 elseif not (shown.marked or shown.freeze) and not shown.guaranteed
  and (c.annotation=='wrong quality' or c.annotation=='low quality') then
  tag=(Nexus.Localization.Text('panel.label.offer_wrong_quality'))
 end
 local want=tostring(shown.name)..' | '..tostring(shown.quality)..' | '..tag..(starred and ' (after its star)' or '')
 if not o then return false,shown,'no card vs '..want end
 local got=o.texts.name.text..' | '..o.texts.quality.text..' | '..o.texts.tag.text
  ..((o.card.star~=nil and o.card.star:IsShown()) and ' (after its star)' or '')
 return got==want and o.card._nexusTag==shown.tag,shown,got..' vs '..want
end
-- The row in the roll box, its shown texts inside it and apart from each
-- other. (Until the main-panel visual correction this also held the row to
-- the height of its name's box: the one-line row. A row's height against
-- its content is S.Lines, checked beside every use of S.Band.)
function S.Band(o)
 local roll=S.Rect(root._rollArea)
 if not (o and o.rect and roll and G.Inside(o.rect,roll,0.01)) then return false,'row outside the roll box' end
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
-- The row's height against its own content (the approved compact row;
-- "Equal base row rhythm must grow for full real text/reason"): what S.Plan
-- says its words need, or the draft's own height for its arrangement when
-- they need no more; a row that holds the selected offer's reason is taller
-- by the draft's 18 pixels, or by that reason's own measured lines when they
-- need more. No text of the row is cut: each box holds its measured lines.
function S.Lines(o)
 if not (o and o.rect) then return false,'no row' end
 local L,card=S.L(),o.card
 local plan=S.Plan(card)
 local need,pixels=plan.need,plan.pixels
 local rec=root._rollRec
 local rr=rec and G.Visible(rec:GetText() or '')~='' and S.Rect(rec) or nil
 if rr and G.Inside(rr,o.rect,0.01) then
  need,pixels=need+math.max(L.reason,math.ceil(rec:GetStringHeight() or 0)),pixels+18
 end
 local height=card:GetHeight() or -1
 if height<need-0.01 or not (math.abs(height-need)<0.01 or S.Drawn(pixels,height)) then
  return false,string.format('row height %.1f is not what its content needs, %.1f, or the draft\'s %d pixels',height,need,pixels)
 end
 for _,k in ipairs({'name','quality','tag'}) do
  if o.texts[k].text~='' and (card[k]:GetHeight() or 0)+0.5<(card[k]:GetStringHeight() or 0) then
   return false,string.format('%s box %.1f is lower than its lines, %.1f',k,card[k]:GetHeight() or -1,card[k]:GetStringHeight() or -1)
  end
 end
 return true,G.Text(o.rect)
end
-- Whether a text's box holds its whole text in the lines it wraps to at the
-- box's width (a status word in its column).
function S.WholeWrapped(card,k) return (card[k]:GetHeight() or 0)+0.5>=(card[k]:GetStringHeight() or 0) end
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

C.scenario('REG-SLOT-0 controls: start-up, Auto OFF, real cards keep their current text, hover and band',function()
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
   local lines,lwhy=S.Lines(o)
   C.expect(lines,'REG-SLOT: card '..i..'\'s row is as tall as its content needs',lwhy)
   local tip=V.Plain(table.concat(V.TooltipLines(o.card:GetScript('OnEnter'),o.card),' '))
   C.guard(tip:find(V.Plain(shown.full),1,true)~=nil,'REG-SLOT: card '..i..'\'s hover shows its complete line',tip)
  end
 end
end)

C.scenario('REG-SLOT-1 one reused card: its own rarity colours its name; an unknown quality stays white; no icon appears',function()
 local first=root._offerCards and root._offerCards[1]
 local states={
  {'own rarity 2',S.Offer('Frostwake Sigil',2),2},
  {'own rarity 3',S.Offer('Frostwake Sigil',3),3},
  {'an unknown own quality and a name ending (Rare)',S.Offer('Frostwake Sigil (Rare)',nil),nil},
  {'no own facts (a quality only in its text)',{text='Frostwake Sigil (Rare)'},nil},
  {'own rarity 2 again',S.Offer('Frostwake Sigil',2),2},
 }
 local counts={}
 for n,st in ipairs(states) do
  local m=Model({cards={st[2]}})
  P.Render(m)
  local o=S.Observe(1)
  if C.setup(o~=nil and o.visible and o.card==first,'REG-SLOT: fixture: the same first card is shown with '..st[1]) then
   local ok,_,detail=S.Meaning(m,1,o)
   C.guard(ok,'REG-SLOT: with '..st[1]..' the card keeps its Readout name, quality and tag',detail)
   counts[n]=#S.Parts(first)
   local fine,why=S.Fallback(o,st[3])
   C.guard(fine,'REG-SLOT: with '..st[1]..' the row shows no icon and its name is '..(st[3] and ('in Echo rarity colour '..st[3]) or 'white 1,1,1: no rarity colour from the text or the earlier card'),why)
  end
 end
 C.guard(counts[1]~=nil and counts[1]==counts[#states],
  'REG-SLOT: the reused card keeps the same regions across renders (none added per render)',tostring(counts[1])..' -> '..tostring(counts[#states]))
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
     C.guard(fine,'REG-SLOT: with '..b[1]..' card '..i..' shows no icon and its name in its current facts\' colour ('..tostring(b[3][i] or 'white')..')',why)
    end
   elseif card then
    C.guard(not card:IsVisible() and not S.AnyVisible(card) and not S.GroundShown(card),'REG-SLOT: with '..b[1]..' card '..i..' and everything in it is hidden')
   end
  end
 end
end)

C.scenario('REG-SLOT-3 at 50, 100, 125 and 150% long names and tags keep name, quality and tag inside their row and apart',function()
 for _,scale in ipairs({0.5,1,1.25,1.5}) do
  local pct=string.format('%d%%',math.floor(scale*100+0.5))
  P.SetPanelScale(scale)
  local function Controls()
   return tostring(root._rollRec and root._rollRec:IsShown())..'/'..tostring(root._autoBtn and root._autoBtn:IsShown())
    ..'/'..tostring(root._menuBtn and root._menuBtn:IsShown())
  end
  P.Render(Model({cards={S.Offer('Frostwake Sigil',2),S.Offer('Hollow Bell',3,'Owned 1 of 2'),S.Offer('Ashen Crown',nil)}}))
  local h0,r0,c0=root:GetHeight(),S.Rect(root._rollArea),Controls()
  -- The rows of the short board, each one line (the name with its phrase
  -- at the row's right end): the height the long board's rows grow from.
  -- (They were the two-line grid row: a line of name over one of quality.)
  local short={}
  for i=1,3 do short[i]=root._offerCards[i]:GetHeight() end
  C.expect(S.BaseRow(short[1]) and S.BaseRow(short[2]) and S.BaseRow(short[3]) and math.abs(short[1]-short[2])<=1 and math.abs(short[2]-short[3])<=1,
   'REG-SLOT: at '..pct..' the three short rows are the one-line compact row: the draft\'s 28 pixels, never under their measured line and pads',
   tostring(short[1])..'/'..tostring(short[2])..'/'..tostring(short[3]))
  P.Render(Model({cards={S.Offer(string.rep('Cinderbound ',8)..'Lattice',2,'Owned 2 of 3'),
   S.Offer('Hollow Bell of the '..string.rep('Ashen ',8)..'Choir',4,'Owned 0 of 1'),
   S.Offer(string.rep('Gravecall ',6)..'Chorus (Rare)',nil,'Owned 1 of 1')}}))
  local h1,r1,c1=root:GetHeight(),S.Rect(root._rollArea),Controls()
  -- Approved panel cleanup ("Full offer names ... Wrap and grow ... No
  -- clipping, ellipsis or arbitrary line cap"): a long name is no longer
  -- shortened in a fixed row, so the panel and the roll box grow by exactly
  -- what the wrapped names add to their rows and by nothing else; the
  -- recommendation and the controls stay as they were.
  -- Main-panel visual correction: what a wrapped name adds is measured from
  -- the same row's own height on the short board (above), which is the
  -- one-line compact row now.
  local extra=0
  for i=1,3 do extra=extra+math.max(0,root._offerCards[i]:GetHeight()-short[i]) end
  C.guard(extra>0 and h1==h0+extra and r0~=nil and r1~=nil and math.abs((r1[4]-r1[2])-(r0[4]-r0[2])-extra)<0.01 and c1==c0,
   'REG-SLOT: at '..pct..' long names wrap: the panel and the roll box grow by exactly their rows\' extra height; the recommendation and controls stay',
   tostring(h0)..'->'..tostring(h1)..' extra '..extra..' '..c0..'->'..c1)
  local want={2,4,nil}
  for i=1,3 do
   local o=S.Observe(i)
   if C.setup(o~=nil and o.visible,'REG-SLOT: fixture: at '..pct..' long card '..i..' is shown') then
    local band,why=S.Band(o)
    C.guard(band,'REG-SLOT: at '..pct..' long card '..i..' keeps its compact row with its texts inside and apart',why)
    local lines,lwhy=S.Lines(o)
    C.expect(lines,'REG-SLOT: at '..pct..' long card '..i..'\'s row is as tall as its wrapped name and its phrase need',lwhy)
    local fine,fwhy=S.Fallback(o,want[i])
    C.guard(fine,'REG-SLOT: at '..pct..' long card '..i..' shows no icon and its name in its own colour',fwhy)
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
-- anything but a texture, the row shows no icon (REG-SLOT). A reused,
-- replaced or hidden card keeps no earlier texture. One lookup per shown
-- offer per layout pass; none on a settled render; no failure is remembered.
-- EXPECT: the id in the facts and the icon (absent at 4ab0b525). GUARD: names,
-- the generated flag, text, hover, band, the row without an icon and passive
-- input. The slot's rarity outline is removed (REG-ROW). Model geometry only:
-- the native icon render is NOT RUN.
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
-- A row that shows an icon: its visuals hold exactly one texture, `path`, in a
-- positive rectangle inside the row, before the name and apart from the
-- texts; its name is in the card's own rarity colour (white when unknown).
function S.IconShown(o,path,q)
 if not (o and o.visible and o.rect) then return false,'card not visible' end
 if #o.paths~=1 or o.paths[1]~=path then return false,'row textures '..S.Paths(o)..', want '..tostring(path) end
 local icon=S.Icon(o)
 if not (icon and icon[3]-icon[1]>0 and icon[4]-icon[2]>0 and G.Inside(icon,o.rect,0.01)) then return false,'icon outside its row' end
 local name=o.texts.name.rect
 if not (name and icon[3]<=name[1]+0.01) then return false,'icon '..G.Text(icon)..' leaves no space before the name' end
 for _,k in ipairs({'name','quality','tag'}) do
  local t=o.texts[k]
  if t.text~='' and t.rect and not G.Apart(icon,t.rect) then return false,'icon '..G.Text(icon)..' overlaps the '..k end
 end
 local named,nwhy=S.Named(o,q)
 if not named then return false,nwhy end
 return true,'icon '..G.Text(icon)
end

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
   C.expect(ok,'REG-ICON: card '..i..' ('..want[3]..') shows the texture of its own spell id inside its row, before the name',why)
   local same,shown,detail=S.Meaning(m,i,o)
   C.guard(same,'REG-ICON: card '..i..' keeps the Readout name, quality and tag',detail)
   local band,bwhy=S.Band(o)
   C.guard(band,'REG-ICON: card '..i..' keeps its compact row in the roll box, its texts inside and apart',bwhy)
   local lines,lwhy=S.Lines(o)
   C.expect(lines,'REG-ICON: card '..i..'\'s row is as tall as its content needs',lwhy)
   local tip=V.Plain(table.concat(V.TooltipLines(o.card:GetScript('OnEnter'),o.card),' '))
   C.guard(tip:find(V.Plain(shown.full),1,true)~=nil,'REG-ICON: card '..i..'\'s hover still shows its complete line',tip)
  end
 end
 local third=S.Observe(3)
 if C.setup(third~=nil and third.visible,'REG-ICON: fixture: offer card 3 is shown') then
  local fine,why=S.Fallback(third,4)
  C.guard(fine,'REG-ICON: card 3, without a spell id, shows no icon, its own or a neighbour\'s',why..' '..S.Paths(third))
 end
 C.expect(S.icon.Asked(200001)==1 and S.icon.Asked(200002)==1,'REG-ICON: each shown offer\'s exact id was looked up once',S.icon.Asked(200001)..'/'..S.icon.Asked(200002))
 S.icon.Restore()
end)

C.scenario('REG-ICON-3 at 50, 100, 125 and 150% the icon stays inside its row beside long names and tags',function()
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
    local lines,lwhy=S.Lines(o)
    C.expect(lines,'REG-ICON: at '..pct..' long card '..i..'\'s row is as tall as its wrapped name and its phrase need',lwhy)
    local ok,iwhy=S.IconShown(o,S.icon.Path(200000+i),q or nil)
    C.expect(ok,'REG-ICON: at '..pct..' long card '..i..' shows its icon inside its row, before the name and apart from its texts',iwhy)
   end
  end
 end
 S.icon.Restore()
 S.Restore()
end)

C.scenario('REG-ICON-4 no id, an id that is not a positive whole number, or a lookup without a texture shows no icon',function()
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
   C.guard(fine,'REG-ICON: '..a[1]..' shows no icon',why..' '..S.Paths(o))
   C.expect(S.icon.Asked(a[2])==1,'REG-ICON: '..a[1]..': the exact id was asked once, and its failure guessed nothing',S.icon.Asked(a[2]))
  end
 end
 -- An id the client must never be asked about: a texture is on offer for each, so only the refusal keeps the row without an icon.
 local huge=2^40
 for _,bad in ipairs({{'zero',0},{'a negative number',-200001},{'a fraction',200001.5},{'a string','200001'},{'a number above the 32-bit range',huge},{'a boolean',true}}) do
  S.icon.Use({[bad[2]]=A,[200001]=A})
  local okRender=pcall(P.Render,Model({cards={S.Echo('Frostwake Sigil',3,bad[2])}}))
  local o=S.Observe(1)
  if C.setup(okRender and o~=nil and o.visible and o.card==first,'REG-ICON: fixture: the first card is shown with '..bad[1]..' as its spell id') then
   local fine,why=S.Fallback(o,3)
   C.guard(fine and #S.icon.calls==0,'REG-ICON: '..bad[1]..' as a spell id is never looked up and shows no icon',why..' '..S.Paths(o)..' lookups '..#S.icon.calls)
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
 C.guard(okNone and none~=nil and none.visible and (S.Fallback(none,2)),'REG-ICON: a client without the lookup renders the row without an icon',S.Paths(none))
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
 C.expect(a and b and c and S.icon.Asked(200019)==1,'REG-ICON: after two icons, an id without a texture leaves the same card without an icon',cwhy..' '..S.Paths(o3))
 P.Render(Model({cards={S.Echo('Frostwake Sigil',2,200001)}}))
 local again=S.IconShown(S.Observe(1),A,2)
 P.Render(Model({cards={},recommendation=''}))
 C.expect(again and not first:IsVisible() and not S.AnyVisible(first) and not S.GroundShown(first) and not S.Stale(first),
  'REG-ICON: with no offer the card that showed an icon is hidden with everything in it and holds no texture')
 P.Render(Model({cards={S.Offer('Hollow Bell',3)}}))
 local o5=S.Observe(1)
 local e,ewhy=S.Fallback(o5,3)
 C.guard(o5.card==first and e and not S.Stale(first),'REG-ICON: a returning offer without a spell id shows no icon, its own or an earlier one',ewhy..' '..S.Paths(o5))
 P.Render(Model({cards={S.Echo('Frostwake Sigil',2,200001)}}))
 local f,fwhy=S.IconShown(S.Observe(1),A,2)
 C.expect(f,'REG-ICON: a returning offer with a spell id shows its texture again',fwhy)
 C.guard(#S.Parts(first)==parts,'REG-ICON: the reused card keeps the same regions (none added per render)',parts..' -> '..#S.Parts(first))
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
 C.expect(empty and S.icon.Asked(200004)==1,'REG-ICON: an id the client has no texture for is asked once and shows no icon',why..' asked '..S.icon.Asked(200004))
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
 C.guard(plain,'REG-ICON: the icon is a plain texture of the card: no frame, button or mouse region of its own')
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

-- REG-ROW (offer-row spacing, the user's "remove the outline boxes around them
-- and fix the spacing" on test.163021 / 89124b3a, as the main-panel visual
-- correction's approved design now has the rows: "fixed inset icon/text/
-- status grid, rarity on its secondary line without counts, selected accent
-- outline/dark fill and full selected reason INSIDE its row once"; "apply
-- existing theme text/muted/accent roles explicitly"; "Equal base row rhythm
-- must grow for full real text/reason, never line-clamp or omit it").
-- A row that is not selected paints no outline: neither a rectangle around
-- the row nor a square around the icon; it shows only its icon and its
-- texts. The selected row alone has a dark fill and the accent outline on
-- its own four edges (S.Outline); nothing is painted around an icon. The
-- icon is a borderless square, the draft's 24 pixels, at the row's left
-- inset; a row without one keeps that square free, so names stay aligned.
-- The approved compact row: the name stands 8 pixels after the square, and
-- at the row's right end the quality, a dot and the status word (S.Columns),
-- on the name's line while they fit it and under the name otherwise; a
-- phrase wider than the text column stands as its two parts under the
-- name, each whole (REG-ROW-3). A row is as tall as its content needs or as
-- the draft draws its arrangement; rows are 2 pixels apart, 3 pixels under
-- the heading and above the text below (S.Rows). (Before it the row was the
-- grid: the quality under the name and the status word in one status
-- column of at most half the row's text room, where a wider status word
-- wrapped.) The status word takes the
-- appearance's accent on the selected row and its text colour elsewhere,
-- and the quality the muted colour (S.Roles), where they were a fixed gold
-- and grey.
-- EXPECT: all of that. GUARD: words, the name's colour, the texture, hover,
-- hidden rows, lookups and passive input. Model geometry only: how it looks
-- in the client is NOT RUN.
function S.TagColour(o,marked)
 local c=SlotSpy.text[o.card.tag]
 local roles=S.Roles()
 return S.Same(c,marked and roles.accent or roles.text),c and string.format('%.2f/%.2f/%.2f',c[1],c[2],c[3]) or 'never set'
end
function S.QualityColour(o)
 local c=SlotSpy.text[o.card.quality]
 return S.Same(c,S.Roles().muted),c and string.format('%.2f/%.2f/%.2f',c[1],c[2],c[3]) or 'never set'
end
function S.Hover(o) return V.Plain(table.concat(V.TooltipLines(o.card:GetScript('OnEnter'),o.card),' ')) end
-- Whether a text's box holds its whole one-line text.
function S.Whole(card,k) return (card[k]:GetWidth() or 0)+0.01>=(card[k]:GetStringWidth() or 0) end

C.scenario('REG-ROW-1 the compact row: only the selected row has its accent outline and dark fill; the icon is a borderless square on the row\'s first line; words and hover stay',function()
 local A,B=S.icon.Path(200001),S.icon.Path(200002)
 S.icon.Use({[200001]=A,[200002]=B})
 local marked=S.Echo('Hollow Bell',3,200002,'Owned 1 of 2')
 marked.highlight=true
 local m=Model({cards={S.Echo('Frostwake Sigil',2,200001),marked,S.Echo('Ashen Crown',4,nil)}})
 P.Render(Model())
 P.Render(m)
 local starts={}
 for i,want in ipairs({{A,2},{B,3},{false,4}}) do
  local o=S.Observe(i)
  if C.setup(o~=nil and o.visible,'REG-ROW: fixture: offer row '..i..' is shown') then
   -- Row 2 is the selected offer (marked.highlight above): the scenario's
   -- own statement, not read from the panel.
   local bare,bwhy=S.Outline(o,i==2)
   C.expect(bare,'REG-ROW: row '..i..(i==2 and ' (marked), the selected row, shows its dark fill and the accent outline on its own four edges, and its icon'
    or ' paints no outline and no fill: it shows only its icon'),bwhy)
   -- The outline belongs to the selected row alone, and there is no accent
   -- bar: the painted colour regions are the four edges or none.
   local edges=0
   for _,v in ipairs(o.visuals or {}) do if v.path==nil then edges=edges+1 end end
   C.expect(edges==(i==2 and 4 or 0),'REG-ROW: row '..i..(i==2 and ' (marked) shows four outline edges and no accent bar' or ' shows no outline edge and no accent bar'),edges)
   if want[1] then
    local shown,swhy=S.IconShown(o,want[1],want[2])
    C.guard(shown,'REG-ROW: row '..i..' still shows the texture of its own spell id and its name in its rarity colour',swhy)
    local fit,fwhy=S.IconFit(o)
    C.expect(fit,'REG-ROW: row '..i..'\'s icon is a borderless square, the draft\'s 24 pixels, at the row\'s left inset',fwhy)
   else
    local none,nwhy=S.Fallback(o,want[2])
    C.guard(none,'REG-ROW: row '..i..', without a spell id, shows no icon and its name in its rarity colour',nwhy)
   end
   local cols,cwhy=S.Columns(o)
   C.expect(cols,'REG-ROW: row '..i..': the name 8 pixels after the icon square, and ending at the row\'s right inset the quality, the dot and the status word (after its star when selected)',cwhy)
   starts[i]=o.texts.name.rect and o.texts.name.rect[1]
   local same,shown,detail=S.Meaning(m,i,o)
   C.guard(same,'REG-ROW: row '..i..' keeps the Readout name, quality and tag',detail)
   local tint,twhy=S.TagColour(o,i==2)
   C.expect(tint,'REG-ROW: row '..i..'\'s status word is in the appearance\'s '..(i==2 and 'accent: the selected row' or 'text colour'),twhy)
   local muted,mwhy=S.QualityColour(o)
   C.expect(muted,'REG-ROW: row '..i..'\'s quality is in the appearance\'s muted colour',mwhy)
   C.guard((o.card._nexusMarked==true)==(i==2),'REG-ROW: row '..i..' keeps its mark',tostring(o.card._nexusMarked))
   C.guard(S.Hover(o):find(V.Plain(shown.full),1,true)~=nil,'REG-ROW: row '..i..'\'s hover still shows its complete line',S.Hover(o))
  end
 end
 C.guard(starts[1]~=nil and starts[1]==starts[2] and starts[2]==starts[3],'REG-ROW: the names of rows with and without an icon start at the same place',
  tostring(starts[1])..'/'..tostring(starts[2])..'/'..tostring(starts[3]))
 -- Row 2 is the selected offer here (marked.highlight above).
 local rows,rwhy=S.Rows(3,2)
 C.expect(rows,'REG-ROW: each row is as tall as its content needs or the draft draws it, 2 pixels from the next, 3 pixels under the heading; the selected row 2 holds its reason inside it, under its lines and 2 pixels above its bottom',rwhy)
 local room,mwhy=S.BodyRoom()
 C.guard(room,'REG-ROW: the reason text is inside the roll box, in a box as tall as its text needs',mwhy)
 S.icon.Restore()
end)

C.scenario('REG-ROW-2 at 50 to 150% and with the 16 px and 2.0 faces: long and old-input rows keep their columns; a shortened text is whole on the hover',function()
 S.icon.Use({[200001]=S.icon.Path(200001),[200002]=S.icon.Path(200002)})
 local function Board()
  return Model({cards={S.Echo(string.rep('Cinderbound ',8)..'Lattice',2,200001,'Owned 2 of 3'),
   S.Echo('Hollow Bell of the '..string.rep('Ashen ',8)..'Choir',4,200002,'Owned 0 of 1'),
   {text=string.rep('Gravecall ',6)..'Chorus (Rare) Owned 1 of 1'}}})
 end
 local function Check(label)
  local m=Board()
  P.Render(Model())
  S.icon.calls={}
  P.Render(m)
  local short=0
  for i=1,3 do
   local o=S.Observe(i)
   if C.setup(o~=nil and o.visible,'REG-ROW: fixture: '..label..' long row '..i..' is shown') then
    local band,why=S.Band(o)
    C.guard(band,'REG-ROW: '..label..' long row '..i..' keeps its texts inside the row and apart',why)
    local lines,lwhy=S.Lines(o)
    C.expect(lines,'REG-ROW: '..label..' long row '..i..' is as tall as its wrapped name and its phrase need',lwhy)
    -- No row of this board is selected.
    local bare,bwhy=S.Outline(o,false)
    local cols,cwhy=S.Columns(o)
    local fit,fwhy=true,''
    if i<3 then fit,fwhy=S.IconFit(o) end
    C.expect(bare and cols and fit,'REG-ROW: '..label..' long row '..i..' has no outline, its icon square and its columns',bwhy..' / '..cwhy..' / '..fwhy)
    if not S.Whole(o.card,'name') then short=short+1 end
    local _,shown=S.Meaning(m,i,o)
    C.guard(S.Hover(o):find(V.Plain(shown.full),1,true)~=nil,'REG-ROW: '..label..' long row '..i..'\'s hover shows its complete line',S.Hover(o))
   end
  end
  C.guard(short==3,'REG-ROW: fixture: '..label..' each long name is wider than one line of its column',short)
  C.guard(S.icon.Asked(200001)==1 and S.icon.Asked(200002)==1 and #S.icon.calls==2,
   'REG-ROW: '..label..' each id is looked up once; the old-input row, a text without facts, is never looked up',#S.icon.calls)
  -- No row of this board is selected: the text is under the rows.
  local rows,rwhy=S.Rows(3)
  C.expect(rows,'REG-ROW: '..label..' the rows keep their band: each as tall as its content needs or the draft draws it, and the text under them 3 pixels below the last',rwhy)
  local room,mwhy=S.BodyRoom()
  C.guard(room,'REG-ROW: '..label..' the text under the rows is inside the roll box, in a box as tall as its text needs',mwhy)
 end
 for _,scale in ipairs({0.5,1,1.25,1.5}) do
  P.SetPanelScale(scale)
  Check('at '..string.format('%d%%',math.floor(scale*100+0.5)))
 end
 P.SetPanelScale(1)
 for _,font in ipairs({G.MODELS.px16,G.MODELS.double}) do
  G.UseFont(font)
  Check('with the '..font.name)
 end
 S.icon.Restore()
 S.Restore()
end)

C.scenario('REG-ROW-3 a phrase wider than the text column stands as its two parts under the name, each whole; a long name keeps the whole column',function()
 local note='Different quality from target (wants 4)'
 P.Render(Model())
 P.Render(Model({cards={S.Echo('Ember Spark',2,nil,note),S.Echo(string.rep('Cinderbound ',8)..'Lattice',2,nil,note)}}))
 local a,b=S.Observe(1),S.Observe(2)
 if not C.setup(a~=nil and a.visible and b~=nil and b.visible and a.texts.tag.text==note and b.texts.tag.text==note,
  'REG-ROW: fixture: a short and a long name, each with the same long status word',a and a.texts.tag.text) then return end
 local half=(a.rect[3]-a.rect[1])/2
 C.setup(a.card.tag:GetStringWidth()>half,'REG-ROW: fixture: that status word is wider than half the row',a.card.tag:GetStringWidth()..' of '..half)
 -- The approved compact row ("Preserve whole readable names/values/
 -- statuses/reasons"): there is no status column. This status word with its
 -- quality is wider than the row's text column, so the phrase stands as its
 -- two parts under the name, the quality and under it the status word, each
 -- whole on one line ending at the row's right inset, beside a short name
 -- as beside a long one; the long name has the whole text column and wraps
 -- there, whole. The checks that stood here held the grid's status column:
 -- at most half the row, the status word wrapped in it beside the short
 -- name and shortened beside the long one, with the name kept a sixth.
 local pa,pb=S.Plan(a.card),S.Plan(b.card)
 C.setup(pa.split and pb.split and pa.tagW<=pa.column and pa.inline==false,
  'REG-ROW: fixture: the quality and that status word together are wider than the text column; the status word alone fits it',
  pa.phrase..' in '..pa.column)
 C.expect(S.Whole(a.card,'tag') and S.WholeWrapped(a.card,'tag') and S.Whole(a.card,'quality') and S.Whole(a.card,'name'),
  'REG-ROW: beside a short name the status word, the quality and the name are all whole',
  a.card.tag:GetWidth()..'x'..a.card.tag:GetHeight()..' for '..a.card.tag:GetStringWidth()..' in lines of '..tostring(a.card.tag:GetStringHeight()))
 local ca,cwa=S.Columns(a)
 local cb,cwb=S.Columns(b)
 C.expect(ca and cb and a.card.tag:GetWidth()==b.card.tag:GetWidth() and a.texts.tag.rect[3]==b.texts.tag.rect[3]
  and a.texts.name.rect[1]==b.texts.name.rect[1],
  'REG-ROW: both rows hold the phrase as its two parts under the name, ending at one right inset; their names start at one text column',
  cwa..' / '..cwb)
 C.expect(S.Whole(b.card,'tag') and b.card.name:GetWidth()==pb.column and S.WholeWrapped(b.card,'name') and not S.Whole(b.card,'name'),
  'REG-ROW: beside a long name the status word is whole on its own line and the name has the whole text column, wrapped whole',
  b.card.tag:GetWidth()..' / '..b.card.name:GetWidth())
 C.guard(S.Hover(b):find(note,1,true)~=nil,'REG-ROW: the status word is whole on the row\'s hover too',S.Hover(b))
 local band,why=S.Band(a)
 C.guard(band,'REG-ROW: the short-name row keeps its texts inside the row and apart',why)
 local lines,lwhy=S.Lines(a)
 C.expect(lines,'REG-ROW: the short-name row is as tall as its name and the two lines of its phrase need',lwhy)
end)

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
SlotSpy.methods.SetTextColor=SlotSpy.saved.SetTextColor
SlotSpy.methods.SetJustifyV=SlotSpy.saved.SetJustifyV

-- V4 last: it loads the addon again (a fresh load) with the saved data.
C.scenario('V4 a centre saved at a fitted size is kept on a fresh load',function()
 -- Two rounds. Each: the chosen 150% on a 640-wide screen, a drag that
 -- saves its centre, then a fresh load on the same screen, where the saved
 -- centre must be the panel's centre at the size the fit applies there.
 --   First the original screen, 640 x 1080, with the original model. The
 --   former 420-unit panel did not fit it at 150% (630 of the 616 that
 --   screen leaves), which is how this scenario got its fitted size. The
 --   approved compact panel is 284 units, 426 at 150%: the fit rule gives
 --   the chosen size whole on this screen, so this round checks the saved
 --   centre at the applied 150%, before and after the load.
 --   Beside it, a 640 x 480 screen, where the fit still reduces the chosen
 --   size: for a panel taller than that screen leaves (three offers with
 --   long names, whose rows wrap, and Details open; taller with or without a
 --   Callboard objective, which a fresh load does not show). This round
 --   checks the saved centre at a size reduced to fit.
 -- The fit rule is the one crimson_panel_scale states: the chosen size,
 -- bounded by what the screen holds of the panel's own width and height
 -- with the 24-unit margin, and never under 50%.
 local function Tall()
  return Model({cards={{text=string.rep('Cinderbound ',8)..'Lattice (Rare)'},
   {text='Hollow Bell of the '..string.rep('Ashen ',8)..'Choir (Epic)'},
   {text=string.rep('Gravecall ',6)..'Chorus (Uncommon)'}}})
 end
 local function Fit(panel,screenH)
  return math.max(0.5,math.min(1.5,(640-24)/panel:GetWidth(),(screenH-24)/panel:GetHeight()))
 end
 -- `reduced`: whether this screen is one the fit reduces the chosen size on
 -- (a fixture fact, checked before and after the load). `details`: Details
 -- as the round needs it (nil leaves it as it is, as the original did).
 local function Round(tag,screenH,model,details,reduced)
  UIParent:SetSize(640,screenH)
  P.SetPanelScale(1.5)
  if details~=nil then P._playDetails=details end
  P.Render(model())
  local r=Fit(root,screenH)
  C.setup(((reduced and r<1.5) or (not reduced and r==1.5)) and root:GetWidth()*1.5<=640-24 and math.abs(root:GetScale()-r)<0.0005,
   tag..': fixture: '..(reduced and '150% is reduced to fit this screen\'s height' or 'this screen holds the 284-unit panel at the chosen 150%'),
   tostring(root:GetScale())..' for a panel '..tostring(root:GetWidth())..' x '..tostring(root:GetHeight()))
  Reset()
  Start(root._contextBuildHit)
  Move.x,Move.y=300,330
  Stop(root._contextBuildHit)
  local sx,sy=Saved()
  C.setup(sx==math.floor(300*r-960+0.5) and sy==math.floor(330*r-540+0.5),tag..': fixture: the drag saved its centre in UIParent units',
   tostring(sx)..','..tostring(sy))
  local db=NexusDB
  H=F.Boot(db,function(h) F.OrbService(h) end)
  P,LM=Nexus.Panel,Nexus.LayoutMetrics
  RM=G.RegionMethods()
  RM.GetEffectiveScale=function(self)
   local parent=self.parent
   return (self.scale or 1)*(parent and parent.GetEffectiveScale and parent:GetEffectiveScale() or 1)
  end
  -- The same screen, font model, offers and Details as before the load.
  -- The fitted size is the fit's for the panel as it is after the load,
  -- which is what the saved centre, kept in UIParent units, is restored
  -- at.
  UIParent:SetSize(640,screenH)
  G.UseFont(G.MODELS.default)
  local saved=F.Serialize(NexusDB)
  P.Show()
  if details~=nil then P._playDetails=details end
  local rendered=P.Render(model())==true
  local fresh=NexusPanel
  r=Fit(fresh,screenH)
  C.setup(rendered and ((reduced and r<1.5) or (not reduced and r==1.5)),
   tag..': fixture: the panel renders after the fresh load, '
    ..(reduced and 'still taller than the screen leaves at 150%' or 'and the screen still holds it at the chosen 150%'),fresh:GetHeight())
  local s=fresh:GetScale()
  local p,rel,relP,x,y=fresh:GetPoint(1)
  C.expect(math.abs(s-r)<0.0005 and fresh:GetNumPoints()==1 and p=='CENTER' and rel==UIParent and relP=='CENTER'
   and math.abs(x*s-sx)<0.5 and math.abs(y*s-sy)<0.5,
   tag..': after a fresh load the saved centre is the centre at the fitted size',
   tostring(p)..' '..tostring(x and x*s)..','..tostring(y and y*s)..' at '..s)
  C.guard(F.Serialize(NexusDB)==saved,tag..': the fresh load writes no position, size or other saved data')
  return fresh
 end
 -- The original screen and model.
 local fresh=Round('V4',1080,Model,nil,false)
 -- The first round's fresh load replaced the addon, its panel and the
 -- harness's own queries. The drag seams this fixture installed at its start
 -- (the root's centre read, UIParent's, and the held-Shift answer) are put
 -- on the fresh panel the same way before the second round's drag.
 root=fresh
 rawset(root,'GetCenter',function() return Move.x,Move.y end)
 rawset(UIParent,'GetCenter',function() return 960,540 end)
 IsShiftKeyDown=function() return ShiftHeld.value end
 -- Beside it: the screen that reduces the chosen size, with a tall panel.
 Round('V4 (640 x 480)',480,Tall,true,true)
end)

-- Held-Shift fixture scope ends: the query saved before the drag helpers returns.
IsShiftKeyDown=RealIsShiftKeyDown

Nexus.DisableOrdinaryAutomation()
C.finish('(review corrections over the harness with modelled hide propagation, effective scale and tooltip owner; native NOT RUN)')
